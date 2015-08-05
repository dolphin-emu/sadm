#! /bin/bash

set -e

test -d $HOME/kythe || git clone https://github.com/google/kythe $HOME/kythe
cd $HOME/kythe
git fetch origin master
git reset --hard origin/master
bazel build -c opt \
    //kythe/cxx/extractor:cxx_extractor \
    //kythe/cxx/indexer/cxx:indexer \
    //kythe/cxx/tools:static_claim \
    //kythe/go/platform/tools:dedup_stream \
    //kythe/go/storage/tools:write_entries \
    //kythe/go/serving/tools:write_tables

builtbin=$(bazel info -c opt bazel-bin)
for target in kythe/cxx/extractor/cxx_extractor \
              kythe/cxx/indexer/cxx/indexer \
              kythe/cxx/tools/static_claim \
              kythe/go/platform/tools/dedup_stream \
              kythe/go/storage/tools/write_entries \
              kythe/go/serving/tools/write_tables; do
    binary=$(basename "${target}")
    cp -f "${builtbin}/${target}" "${HOME}/bin/${binary}"
done

test -d $HOME/csui || git clone https://github.com/dolphin-emu/codesearch-ui $HOME/csui
cd $HOME/csui
git fetch origin master
git reset --hard origin/master
go build -o ~/bin/csindexer indexer/indexer.go
