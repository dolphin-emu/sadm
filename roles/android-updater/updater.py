#! /usr/bin/env python3
"""Updates the Play Store listing for Dolphin to follow an update track."""

import argparse
import hashlib
import httplib2
import io
import requests
import sys

from apiclient import discovery
from apiclient import http as googhttp
from googleapiclient.errors import HttpError
from oauth2client import service_account

_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
_UPDATE_URL_FMT = "https://dolphin-emu.org/update/latest/%s/"
_ARTIFACT_ANDROID_SYSTEM = "Android"
_APK_MIME = "application/vnd.android.package-archive"
_AAB_MIME = "application/octet-stream"

_REVIEW_NOT_ALLOWED = "Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true. Once committed, the changes in this edit can be sent for review from the Google Play Console UI."


def _get_playstore_service(key_file):
    credentials = service_account.ServiceAccountCredentials.from_json_keyfile_name(
        key_file, scopes=[_PUBLISHER_SCOPE]
    )
    http = httplib2.Http()
    http = credentials.authorize(http)
    return discovery.build("androidpublisher", "v3", http=http)


def _get_dolphin_update_info(track):
    return requests.get(_UPDATE_URL_FMT % track).json()


def _fetch_aab_artifact(apk_url, dolphin_track):
    # AABs are not currently registered as artifacts on the website, since it does not support
    # the concept of "hidden" artifacts - all artifacts are user visible. On dev builds, hack
    # around to find the URL for an AAB from the APK url. This needs duplication of the sharded
    # URL hasher. On release builds, just replace the file extension.
    if dolphin_track == "beta":
        aab_url = apk_url.replace(".apk", ".aab")
    else:
        filename = apk_url.split("/")[-1].replace(".apk", ".aab")
        url_base = apk_url.rsplit("/", 3)[0]
        sha = hashlib.sha256(filename.encode("utf-8")).hexdigest()
        aab_url = "/".join((url_base, sha[0:2], sha[2:4], filename))

    resp = requests.get(aab_url)
    if resp.status_code != 200:
        return None
    return resp.content


def _get_playstore_version(play, package_name, playstore_track):
    edit_id = play.edits().insert(body={}, packageName=package_name).execute()["id"]
    tracks = (
        play.edits().tracks().list(editId=edit_id, packageName=package_name).execute()
    )
    for track in tracks["tracks"]:
        if track["track"] != playstore_track:
            continue
        return track["releases"][0].get("name")


def _commit_edit(play, edit_id, package_name):
    try:
        play.edits().commit(editId=edit_id, packageName=package_name).execute()
    except HttpError as err:
        # If we have an unresolved policy violation in Google Play, we're allowed to use the API to
        # upload builds but not to send them off for review
        if err.resp.status == 400 and err._get_reason() == _REVIEW_NOT_ALLOWED:
            play.edits().commit(editId=edit_id, packageName=package_name, changesNotSentForReview='true').execute()
        else:
            raise


def _find_or_upload_aab(play, package_name, aab):
    edit_id = play.edits().insert(body={}, packageName=package_name).execute()["id"]
    play_aabs = (
        play.edits()
        .bundles()
        .list(editId=edit_id, packageName=args.package_name)
        .execute()["bundles"]
    )

    aab_sha256 = hashlib.sha256(aab).hexdigest()
    for known_aab in play_aabs:
        if known_aab["sha256"] == aab_sha256:
            return known_aab["versionCode"]

    aab = io.BytesIO(aab)
    upload_response = (
        play.edits()
        .bundles()
        .upload(
            editId=edit_id,
            packageName=package_name,
            media_body=googhttp.MediaIoBaseUpload(aab, mimetype=_AAB_MIME),
        )
        .execute()
    )
    _commit_edit(play, edit_id, package_name)
    return upload_response["versionCode"]


def _find_or_upload_apk(play, package_name, apk):
    edit_id = play.edits().insert(body={}, packageName=package_name).execute()["id"]
    play_apks = (
        play.edits()
        .apks()
        .list(editId=edit_id, packageName=args.package_name)
        .execute()["apks"]
    )

    apk_sha256 = hashlib.sha256(apk).hexdigest()
    for known_apk in play_apks:
        if known_apk["binary"]["sha256"] == apk_sha256:
            return known_apk["versionCode"]

    apk = io.BytesIO(apk)
    upload_response = (
        play.edits()
        .apks()
        .upload(
            editId=edit_id,
            packageName=package_name,
            media_body=googhttp.MediaIoBaseUpload(apk, mimetype=_APK_MIME),
        )
        .execute()
    )
    _commit_edit(play, edit_id, package_name)
    return upload_response["versionCode"]


def _update_playstore_track(play, package_name, playstore_track, version_code, info):
    edit_id = play.edits().insert(body={}, packageName=package_name).execute()["id"]
    track_response = (
        play.edits()
        .tracks()
        .update(
            editId=edit_id,
            packageName=package_name,
            track=playstore_track,
            body={
                "releases": [
                    {
                        "name": info["shortrev"],
                        "versionCodes": [str(version_code)],
                        "status": "completed",
                    }
                ]
            },
        )
        .execute()
    )
    _commit_edit(play, edit_id, package_name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--package_name", type=str, required=True)
    parser.add_argument("--dolphin_track", type=str, required=True)
    parser.add_argument("--playstore_track", type=str, required=True)
    parser.add_argument("--service_key_file", type=str, required=True)
    args = parser.parse_args()

    play = _get_playstore_service(args.service_key_file)

    latest_dolphin_info = _get_dolphin_update_info(args.dolphin_track)
    playstore_version = _get_playstore_version(
        play, args.package_name, args.playstore_track
    )

    if latest_dolphin_info["shortrev"] == playstore_version:
        print(
            "Latest dolphin version %s is already on Play."
            % latest_dolphin_info["shortrev"]
        )
        sys.exit(0)

    edit_id = (
        play.edits().insert(body={}, packageName=args.package_name).execute()["id"]
    )

    for artifact in latest_dolphin_info["artifacts"]:
        if artifact["system"] == _ARTIFACT_ANDROID_SYSTEM:
            break
    else:
        print("No Android artifact found. Exiting.")
        sys.exit(0)

    # Try fetching an AAB first for the artifact, if not found fallback to APK.
    aab = _fetch_aab_artifact(artifact["url"], args.dolphin_track)
    if aab is not None:
        version_code = _find_or_upload_aab(play, args.package_name, aab)
    else:
        apk = requests.get(artifact["url"]).content
        version_code = _find_or_upload_apk(play, args.package_name, apk)

    _update_playstore_track(
        play, args.package_name, args.playstore_track, version_code, latest_dolphin_info
    )
