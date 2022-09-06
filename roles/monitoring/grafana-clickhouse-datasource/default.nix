{ stdenv, lib, fetchurl, unzip }:

stdenv.mkDerivation rec {
  pname = "grafana-clickhouse-datasource";
  version = "2.0.0";

  src = fetchurl {
    name = "${pname}-${version}.zip";
    url = "https://grafana.com/api/plugins/${pname}/versions/${version}/download?os=linux&arch=amd64";
    hash = "sha256-JgGwMpqRXtOusMiYsDdTa1XWXHcqXBrmluQCbsGbyo0=";
  };

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    cp -R "." "$out"
    chmod -R a-w "$out"
    chmod u+w "$out"
  '';

  meta = with lib; {
    description = "ClickHouse data source for Grafana";
    license = licenses.asl20;
    maintainers = with maintainers; [ delroth ];
    platforms = platforms.unix;
  };
}
