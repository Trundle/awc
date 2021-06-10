{ clang, clangStdenv, dockerTools, oci-image-tool, skopeo }:

clangStdenv.mkDerivation rec {
  name = "swift-bin";
  version = "5.4";

  src = dockerTools.pullImage {
    imageName = "swift";
    imageDigest = "sha256:d32b9d6dc9663b4e2f95e2ce41694f01cdfb9b37253bb14d668490b3858a82ca";
    finalImageTag = "5.4-focal";
    sha256 = "sha256-0cdXErxTXArFvOijytlFjUTozC7WYssUyQag2c0Ystk=";
  };

  dontPatchELF = true;
  dontStrip = true;

  sourceRoot = "unpacked";

  unpackPhase = ''
    runHook preUnpack

    ${skopeo}/bin/skopeo --insecure-policy copy docker-archive:$src oci:.:${version} >/dev/null
    ${oci-image-tool}/bin/oci-image-tool unpack --ref name=${version} . unpacked

    runHook postUnpack
  '';

  installPhase = ''
    mkdir -p $out

    rm usr/bin/clang*

    cp -r usr lib $out/

    interpreter=$(ls $out/lib/x86_64-linux-gnu/ld-*.so)
    find $out/usr/bin -type f -executable -exec patchelf --set-interpreter $interpreter {} \;
    find $out/usr/bin -type f -executable -exec patchelf --set-rpath "$out/lib/x86_64-linux-gnu:$out/usr/lib:$out/usr/lib/x86_64-linux-gnu:$out/usr/lib/swift/linux" {} \;
    find $out/lib/ $out/usr/lib -type f -name 'lib*.so*' -exec patchelf --set-rpath "$out/lib/x86_64-linux-gnu:$out/usr/lib:$out/usr/lib/x86_64-linux-gnu:$out/usr/lib/swift/linux" {} \;
  '';

  propagatedBuildInputs = [
    clang
  ];
}
