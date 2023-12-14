{ xng-flake-utils, ... }:
let
  genCheckFromExample =
    { pkgs, name, partitions, hardFp ? false, extraBinaryBlobs ? { }, xngOps }:
    let
      exampleDir = xngOps.dev + "/xre-examples";
    in
    xng-flake-utils.lib.buildXngSysImage {
      inherit pkgs extraBinaryBlobs hardFp name xngOps;
      xcf = pkgs.runCommandNoCC "patch-src" { } ''
        cp -r ${exampleDir + "/${name}/xml"} $out/
        for file in $(find $out -name hypervisor.xml)
        do
          substituteInPlace "$file" --replace 'baseAddr="0xE0001000"' 'baseAddr="0xE0000000"'
        done
      '';
      partitions = pkgs.lib.mapAttrs (_: v: { src = exampleDir + "/${name}/${v}"; }) partitions;
    };

  genCheckDrvs = { pkgs, examples, xngOps, lithOsOps, ... }:
    # the XNG examples
    (builtins.listToAttrs (builtins.map
      ({ name, ... } @ args: {
        name = "example-" + name;
        value = genCheckFromExample (args // { inherit pkgs xngOps; });
      })
      examples)
    ) // {
      inherit xngOps lithOsOps;
    };
  buildXngOps = { pkgs, srcs, version }: xng-flake-utils.lib.buildXngOps { inherit pkgs version; src = srcs.xng; };
  buildLithOsOps = { pkgs, srcs, version }: xng-flake-utils.lib.buildLithOsOps { inherit pkgs version; src = srcs.lithos; };

in
{ pkgs, examples, srcs, xngVersion, ... }:
with pkgs.lib;
mapAttrs'
  (name: value: nameValuePair
    (
      xng-flake-utils.lib.replaceDots "xng-${xngVersion}-${name}"
    )
    value)
  (genCheckDrvs {
    inherit pkgs examples;
    xngOps = buildXngOps {
      inherit pkgs srcs;
      version = xngVersion;
    };
    lithOsOps = buildLithOsOps {
      inherit pkgs srcs;
      version = lithOsVersion;
    };
  })
