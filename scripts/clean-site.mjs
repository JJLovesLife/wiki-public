import { rm } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const generatedPaths = ["content", "public", ".quartz", ".quartz-cache", "tsconfig.tsbuildinfo"];

await Promise.all(
  generatedPaths.map((target) => rm(path.join(root, target), { recursive: true, force: true })),
);

console.log("Removed generated Quartz artifacts");
