import { execFile } from "node:child_process";
import { cp, mkdir, rm, readFile, readdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";

const root = process.cwd();
const contentDir = path.join(root, "content");
const execFileAsync = promisify(execFile);

function toGitPath(filePath) {
  return path.relative(root, filePath).split(path.sep).join("/");
}

async function gitLogDates(source) {
  const gitPath = toGitPath(source);

  try {
    const [{ stdout: modifiedStdout }, { stdout: historyStdout }] =
      await Promise.all([
        execFileAsync("git", ["log", "-1", "--format=%cI", "--", gitPath], {
          cwd: root,
        }),
        execFileAsync(
          "git",
          ["log", "--follow", "--format=%cI", "--", gitPath],
          { cwd: root },
        ),
      ]);

    const modified = modifiedStdout.trim().split(/\r?\n/).filter(Boolean).at(0);
    const history = historyStdout.trim().split(/\r?\n/).filter(Boolean);
    const created = history.at(-1);

    return { created, modified };
  } catch (error) {
    console.warn(`Warning: couldn't read git dates for ${gitPath}`);
    return {};
  }
}

function frontmatterValue(value) {
  return JSON.stringify(value);
}

function upsertFrontmatter(markdown, values) {
  const entries = Object.entries(values).filter(
    ([, value]) => value !== undefined,
  );
  if (entries.length === 0) return markdown;

  const lines = markdown.split(/\r?\n/);
  const frontmatterLines = entries.map(
    ([key, value]) => `${key}: ${frontmatterValue(value)}`,
  );

  if (lines[0] !== "---") {
    return `---\n${frontmatterLines.join("\n")}\n---\n\n${markdown}`;
  }

  const end = lines.findIndex((line, index) => index > 0 && line === "---");
  if (end === -1) {
    return `---\n${frontmatterLines.join("\n")}\n---\n\n${markdown}`;
  }

  const existing = lines.slice(1, end);
  const rest = lines.slice(end);
  const replacementKeys = new Set(entries.map(([key]) => key));
  const kept = existing.filter((line) => {
    const match = line.match(/^([A-Za-z0-9_-]+):/);
    return !match || !replacementKeys.has(match[1]);
  });

  return ["---", ...kept, ...frontmatterLines, ...rest].join("\n");
}

async function writeMarkdownWithFrontmatter(
  source,
  destination,
  extraFrontmatter = {},
) {
  const markdown = await readFile(source, "utf8");
  const dates = await gitLogDates(source);
  await mkdir(path.dirname(destination), { recursive: true });
  await writeFile(
    destination,
    upsertFrontmatter(markdown, { ...extraFrontmatter, ...dates }),
  );
}

async function addGitDatesToCopiedMarkdown(sourceDir, destinationDir) {
  const entries = await readdir(sourceDir, { withFileTypes: true });

  await Promise.all(
    entries.map(async (entry) => {
      const source = path.join(sourceDir, entry.name);
      const destination = path.join(destinationDir, entry.name);

      if (entry.isDirectory()) {
        await addGitDatesToCopiedMarkdown(source, destination);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        await writeMarkdownWithFrontmatter(source, destination);
      }
    }),
  );
}

async function writeMarkdownWithFrontmatterIfExists(
  source,
  destination,
  extraFrontmatter = {},
) {
  if (!existsSync(source)) return;
  await writeMarkdownWithFrontmatter(source, destination, extraFrontmatter);
}

await rm(contentDir, { recursive: true, force: true });
await mkdir(contentDir, { recursive: true });

await cp(path.join(root, "wiki"), path.join(contentDir, "wiki"), {
  recursive: true,
});
await addGitDatesToCopiedMarkdown(
  path.join(root, "wiki"),
  path.join(contentDir, "wiki"),
);

await writeMarkdownWithFrontmatterIfExists(
  path.join(root, "README.md"),
  path.join(contentDir, "index.md"),
  {
    title: "LLM Wiki",
  },
);
await writeMarkdownWithFrontmatterIfExists(
  path.join(root, "README.md"),
  path.join(contentDir, "README.md"),
);
await writeMarkdownWithFrontmatterIfExists(
  path.join(root, "AGENTS.md"),
  path.join(contentDir, "AGENTS.md"),
);

console.log("Prepared Quartz content from wiki/, README.md, and AGENTS.md");
