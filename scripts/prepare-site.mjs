import { cp, mkdir, rm, copyFile, readFile, writeFile } from "node:fs/promises"
import { existsSync } from "node:fs"
import path from "node:path"

const root = process.cwd()
const contentDir = path.join(root, "content")

async function copyIfExists(source, destination) {
  if (!existsSync(source)) return
  await mkdir(path.dirname(destination), { recursive: true })
  await copyFile(source, destination)
}

await rm(contentDir, { recursive: true, force: true })
await mkdir(contentDir, { recursive: true })

await cp(path.join(root, "wiki"), path.join(contentDir, "wiki"), {
  recursive: true,
})

if (existsSync(path.join(root, "README.md"))) {
  const readme = await readFile(path.join(root, "README.md"), "utf8")
  const homepage = `---\ntitle: LLM Wiki\n---\n\n${readme}`
  await writeFile(path.join(contentDir, "index.md"), homepage)
}
await copyIfExists(path.join(root, "README.md"), path.join(contentDir, "README.md"))
await copyIfExists(path.join(root, "AGENTS.md"), path.join(contentDir, "AGENTS.md"))

console.log("Prepared Quartz content from wiki/, README.md, and AGENTS.md")
