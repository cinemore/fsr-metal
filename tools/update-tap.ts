import { copyFile } from "node:fs/promises";
import { resolve } from "node:path";

const [tag, tap] = Bun.argv.slice(2);
if (!tag || !/^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(tag) || !tap) {
  throw new Error("Usage: bun tools/update-tap.ts v0.1.0 /path/to/homebrew-tap");
}
const directory = resolve(tap);
function git(...args: string[]) {
  const result = Bun.spawnSync(["git", "-C", directory, ...args], { stdout: "inherit", stderr: "inherit" });
  if (result.exitCode !== 0) throw new Error("git " + args.join(" ") + " failed");
}
await copyFile(new URL("../dist/" + tag + "/Formula/fsr-metal.rb", import.meta.url), resolve(directory, "Formula/fsr-metal.rb"));
git("config", "user.name", "github-actions[bot]");
git("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com");
git("add", "Formula/fsr-metal.rb");
const diff = Bun.spawnSync(["git", "-C", directory, "diff", "--cached", "--quiet"], { stdout: "ignore", stderr: "inherit" });
if (diff.exitCode === 0) process.exit(0);
if (diff.exitCode !== 1) throw new Error("Could not inspect staged tap changes");
git("commit", "-m", "chore: update fsr-metal formula for " + tag);
for (let attempt = 0; attempt < 3; attempt++) {
  const result = Bun.spawnSync(["git", "-C", directory, "push", "origin", "HEAD:main"], { stdout: "inherit", stderr: "inherit" });
  if (result.exitCode === 0) process.exit(0);
  git("pull", "--rebase", "origin", "main");
}
throw new Error("Tap push failed after three attempts");
