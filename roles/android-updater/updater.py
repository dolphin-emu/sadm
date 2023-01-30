#! /usr/bin/env python3
"""Updates the Play Store listing for Dolphin to follow an update track."""

import argparse
import httplib2
import io
import requests
import sys

from apiclient import discovery
from apiclient import http as googhttp
from oauth2client import service_account

_PUBLISHER_SCOPE = 'https://www.googleapis.com/auth/androidpublisher'
_UPDATE_URL_FMT = 'https://dolphin-emu.org/update/latest/%s/'
_ARTIFACT_ANDROID_SYSTEM = 'Android'
_APK_MIME = 'application/vnd.android.package-archive'


def _get_playstore_service(key_file):
    credentials = service_account.ServiceAccountCredentials.from_json_keyfile_name(
        key_file, scopes=[_PUBLISHER_SCOPE])
    http = httplib2.Http()
    http = credentials.authorize(http)
    return discovery.build('androidpublisher', 'v3', http=http)


def _get_dolphin_update_info(track):
    return requests.get(_UPDATE_URL_FMT % track).json()


def _get_playstore_version(play, package_name, playstore_track):
    edit_id = play.edits().insert(
        body={}, packageName=package_name).execute()['id']
    tracks = play.edits().tracks().list(
        editId=edit_id, packageName=package_name).execute()
    for track in tracks['tracks']:
        if track['track'] != playstore_track:
            continue
        return track['releases'][0].get('name')


def _upload_new_playstore_apk(play, package_name, playstore_track, apk, info):
    edit_id = play.edits().insert(
        body={}, packageName=package_name).execute()['id']
    apk_response = play.edits().apks().upload(
        editId=edit_id,
        packageName=package_name,
        media_body=googhttp.MediaIoBaseUpload(apk,
                                              mimetype=_APK_MIME)).execute()
    track_response = play.edits().tracks().update(
        editId=edit_id,
        packageName=package_name,
        track=playstore_track,
        body={
            'releases': [{
                'name': info['shortrev'],
                'versionCodes': [str(apk_response['versionCode'])],
                'status': 'completed'
            }]
        }).execute()
    play.edits().commit(editId=edit_id, packageName=package_name).execute()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--package_name', type=str, required=True)
    parser.add_argument('--dolphin_track', type=str, required=True)
    parser.add_argument('--playstore_track', type=str, required=True)
    parser.add_argument('--service_key_file', type=str, required=True)
    args = parser.parse_args()

    play = _get_playstore_service(args.service_key_file)

    latest_dolphin_info = _get_dolphin_update_info(args.dolphin_track)
    playstore_version = _get_playstore_version(play, args.package_name,
                                               args.playstore_track)

    if latest_dolphin_info['shortrev'] == playstore_version:
        print('Latest dolphin version %s is already on Play.' %
              latest_dolphin_info['shortrev'])
        sys.exit(0)

    for artifact in latest_dolphin_info['artifacts']:
        if artifact['system'] == _ARTIFACT_ANDROID_SYSTEM:
            break
    else:
        print('No Android artifact found. Exiting.')
        sys.exit(1)

    apk = io.BytesIO(requests.get(artifact['url']).content)
    _upload_new_playstore_apk(play, args.package_name, args.playstore_track,
                              apk, latest_dolphin_info)
