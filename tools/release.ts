import { cp, mkdir, chmod } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const binary = "fsr-metal";
const bundle = "FSRMetal_FSRMetal.bundle";
const tag = Bun.argv[2];
if (!tag || !/^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(tag)) {
  throw new Error("Usage: bun tools/release.ts v0.1.0");
}
const version = tag.slice(1);
const destination = join(root, "dist", tag);

function run(command: string[], cwd = root): string {
  const result = Bun.spawnSync(command, { cwd, stdout: "pipe", stderr: "inherit" });
  if (result.exitCode !== 0) throw new Error(command.join(" ") + " failed (" + result.exitCode + ")");
  const output = result.stdout.toString().trim();
  if (output) console.log(output);
  return output;
}
await mkdir(destination, { recursive: true });
const staging = join(destination, "staging");
await mkdir(staging, { recursive: false });
const checksums: Record<string, string> = {};

for (const architecture of ["arm64", "x86_64"]) {
  run(["swift", "build", "-c", "release", "--arch", architecture, "--product", binary]);
  const products = run(["swift", "build", "-c", "release", "--arch", architecture, "--show-bin-path"]).split("\n").at(-1)!;
  const bin = join(staging, binary + "-macos-" + architecture, "bin");
  await mkdir(bin, { recursive: true });
  await cp(join(products, binary), join(bin, binary));
  await chmod(join(bin, binary), 0o755);
  await cp(join(products, bundle), join(bin, bundle), { recursive: true });
}
const universal = join(staging, binary + "-macos-universal", "bin");
await mkdir(universal, { recursive: true });
run(["lipo", "-create", join(staging, binary + "-macos-arm64", "bin", binary),
     join(staging, binary + "-macos-x86_64", "bin", binary), "-output", join(universal, binary)]);
await chmod(join(universal, binary), 0o755);
await cp(join(staging, binary + "-macos-arm64", "bin", bundle), join(universal, bundle), { recursive: true });

const native = process.arch === "arm64" ? "arm64" : "x86_64";
for (const architecture of ["arm64", "x86_64", "universal"]) {
  const archiveName = binary + "-macos-" + architecture;
  const staged = join(staging, archiveName);
  for (const file of ["LICENSE", "THIRD-PARTY.md", "README.md", "README-zh.md", "VALIDATION.md"]) await cp(join(root, file), join(staged, file));
  if (architecture === native || architecture === "universal") {
    const executable = join(staged, "bin", binary);
    if (run([executable, "--version"]) !== version) throw new Error("CLI version must match release tag");
    run([executable, "--self-test"]);
  }
  const archive = join(destination, archiveName + ".tar.gz");
  run(["tar", "-C", staging, "-czf", archive, archiveName]);
  const checksum = new Bun.CryptoHasher("sha256").update(await Bun.file(archive).arrayBuffer()).digest("hex");
  checksums[architecture] = checksum;
  await Bun.write(archive + ".sha256", checksum + "  " + archiveName + ".tar.gz\n");
}

function formula(assetBase: string): string {
  return `class FsrMetal < Formula
  desc "Native Apple Metal FSR 1 image upscaling CLI"
  homepage "https://github.com/cinemore/fsr-metal"
  version "${version}"
  license "MIT"

  depends_on macos: :ventura

  if Hardware::CPU.arm?
    url "${assetBase}/fsr-metal-macos-arm64.tar.gz"
    sha256 "${checksums.arm64}"
  else
    url "${assetBase}/fsr-metal-macos-x86_64.tar.gz"
    sha256 "${checksums.x86_64}"
  end

  def install
    libexec.install "bin/fsr-metal"
    libexec.install "bin/FSRMetal_FSRMetal.bundle"
    (bin/"fsr-metal").write <<~SH
      #!/bin/sh
      exec "#{libexec}/fsr-metal" "$@"
    SH
  end

  test do
    assert_match "FSRMetal self-test", shell_output("#{bin}/fsr-metal --self-test")
  end
end
`;
}
await mkdir(join(destination, "Formula"), { recursive: true });
await mkdir(join(destination, "local", "Formula"), { recursive: true });
await Bun.write(join(destination, "Formula", binary + ".rb"),
  formula("https://github.com/cinemore/" + binary + "/releases/download/" + tag));
await Bun.write(join(destination, "local", "Formula", binary + ".rb"), formula(new URL("file://" + destination).href));
await Bun.write(join(destination, "manifest.json"), JSON.stringify({ binary, tag, bundle, checksums }, null, 2) + "\n");
console.log("Release assets and checksum-backed Homebrew formulas: " + destination);
