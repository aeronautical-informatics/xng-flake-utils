{ pkgs, xng-flake-utils }:
let
  xngVersion = "1.4.7";
  lithOsVersion = "2.0.2";
  srcs = {
    xng = pkgs.requireFile {
      name = "14-033.094.ops+smp+armv7a-vmsa-tz+zynq7000.r22422.tbz2";
      url = "http://fentiss.com";
      hash = "sha256-P1q5UxHcZHNCJfguHuChIvhJ/DN///ZPfYx+p7UiRXQ=";
    };
    lithos = pkgs.requireFile {
      name = "21-004.080.ops.r8942.tbz2";
      url = "https://fentiss.com";
      hash = "sha256-ubJD7EILrp4VE2rAtADWwrIrSiOx2u0pkZU63M9bBjk=";
    };
  };
  examples = [
    {
      name = "hello_world";
      partitions.Partition0 = "hello_world.c";
      extraBinaryBlobs = { "0x00050000" = ./testblob; };
    }
    {
      name = "queuing_port";
      partitions.src_partition = "src0.c";
      partitions.dst_partition = "dst0.c";
    }
    # this example doesn't work, since it is actually two independent hypervisor images
    # reset_hypervisor = genCheckFromExample {
    #   name = "reset_hypervisor";
    #   xcf = exampleDir + "/reset_hypervisor/xml";
    # };
    {
      name = "sampling_port";
      partitions.src_partition = "src0.c";
      partitions.dst_partition0 = "dst0.c";
      partitions.dst_partition1 = "dst1.c";
    }
    {
      name = "sampling_port_smp";
      partitions.Partition0 = "partition0.c";
      partitions.Partition1 = "partition1.c";
    }
    {
      name = "system_timer";
      partitions.Partition0 = "system_timer.c";
    }
    {
      name = "vfp";
      partitions.Partition0 = "vfp0.c";
      partitions.Partition1 = "vfp1.c";
      hardFp = true;
    }
  ];
  xngChecks = import ./xng-checks.nix { inherit xng-flake-utils; };
in
xngChecks { inherit pkgs examples srcs xngVersion lithOsVersion; }
