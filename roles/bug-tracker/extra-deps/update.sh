#!/usr/bin/env bash

if ! [ -d "$redmine" ]; then
  echo "error: could not locate redmine, ensure you follow README instructions"
  exit 1
fi

dir="$(dirname "$0")"
cd "${dir}"

for file in "gemset.nix" "Gemfile.combined" "Gemfile.combined.lock"; do
  if [ -f ${file} ]; then
    rm ${file}
  fi
done

# Locate Redmine's Gemfile by first finding its ruby env, then asking it nicely
# for its environment.
redmineRuby=$(head -1 $redmine/share/redmine/bin/rails | cut -c 3-)
redmineGemfile=$($redmineRuby -e "print ENV['BUNDLE_GEMFILE']")

cat $redmineGemfile Gemfile > Gemfile.combined

BUNDLE_GEMFILE=Gemfile.combined bundle lock --add-platform ruby
BUNDLE_GEMFILE=Gemfile.combined bundle lock --remove-platform x86_64-linux
bundix -l --gemfile=Gemfile.combined --lockfile=Gemfile.combined.lock
