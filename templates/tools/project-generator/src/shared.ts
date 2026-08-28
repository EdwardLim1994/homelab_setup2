import { execFileSync } from "node:child_process";
import {
	existsSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import {
	addProjectConfiguration,
	names,
	type Tree,
	updateJson,
} from "@nx/devkit";

export interface NestScaffoldOptions {
	name: string;
	directory?: string;
}

/** Run the NestJS CLI, preferring an installed `nest`, falling back to npx. */
function runNestNew(cwd: string, name: string) {
	const args = [
		"new",
		name,
		"--skip-install",
		"--skip-git",
		"--package-manager",
		"npm",
		"--language",
		"ts",
	];
	try {
		execFileSync("nest", ["--version"], { stdio: "ignore" });
		execFileSync("nest", args, { cwd, stdio: "inherit" });
	} catch {
		// no global/local nest CLI - let npx fetch it
		execFileSync("npx", ["--yes", "@nestjs/cli", ...args], {
			cwd,
			stdio: "inherit",
		});
	}
}

/**
 * Copy every file from `srcDir` into the Tree under `destRoot`, verbatim (no
 * templating). Use for static template assets that must not be run through EJS.
 */
export function copyDirIntoTree(tree: Tree, srcDir: string, destRoot: string) {
	for (const entry of readdirSync(srcDir, { withFileTypes: true })) {
		if (entry.name === ".git" || entry.name === "node_modules") continue;
		const abs = path.join(srcDir, entry.name);
		const rel = path.posix.join(destRoot, entry.name);
		if (entry.isDirectory()) {
			copyDirIntoTree(tree, abs, rel);
		} else {
			tree.write(rel, readFileSync(abs));
		}
	}
}

// opencode discovers skills from `.opencode/skills/<name>/SKILL.md`
const SKILL_ROOTS = [".opencode/skills"];

interface SkillsLock {
	version: number;
	skills: Record<string, unknown>;
}

/**
 * Copy the generator's bundled third-party agent skills
 * (`<generatorDir>/files/curated-skills/**` + `curated-skills-lock.json`) into
 * `.opencode/skills/` at the workspace root, merging `skills-lock.json`.
 */
export function addCuratedSkills(tree: Tree, generatorDir: string) {
	const src = path.join(generatorDir, "files/curated-skills");
	for (const root of SKILL_ROOTS) {
		copyDirIntoTree(tree, src, root);
	}

	const incoming = JSON.parse(
		readFileSync(
			path.join(generatorDir, "files/curated-skills-lock.json"),
			"utf8",
		),
	) as SkillsLock;
	if (tree.exists("skills-lock.json")) {
		updateJson<SkillsLock>(tree, "skills-lock.json", (existing) => ({
			version: incoming.version,
			skills: { ...existing.skills, ...incoming.skills },
		}));
	} else {
		tree.write("skills-lock.json", `${JSON.stringify(incoming, null, 2)}\n`);
	}
}

/**
 * Scaffold a fresh NestJS project with the real Nest CLI in a temp dir, then
 * copy the result into the Tree under `<directory>/<name>` (directory: `apps`).
 */
export function scaffoldNestProject(tree: Tree, options: NestScaffoldOptions) {
	const projectNames = names(options.name);
	const projectRoot = path.posix.join(
		options.directory ?? "apps",
		projectNames.fileName,
	);

	if (tree.exists(projectRoot)) {
		throw new Error(`${projectRoot} already exists`);
	}

	const workDir = mkdtempSync(path.join(tmpdir(), "nest-"));
	try {
		runNestNew(workDir, projectNames.fileName);
		const scaffold = path.join(workDir, projectNames.fileName);
		if (!existsSync(scaffold)) {
			throw new Error("nest new did not produce a project");
		}
		copyDirIntoTree(tree, scaffold, projectRoot);
	} finally {
		rmSync(workDir, { recursive: true, force: true });
	}

	return { names: projectNames, projectRoot };
}

/**
 * Register the scaffolded project as an Nx application. build/serve/test
 * delegate to the project's own npm scripts (`nest build`, `nest start --watch`,
 * `vitest run`).
 *
 * ponytail: run-commands wrapper, swap for @nx/nest executors if this grows.
 */
export function registerNestApp(tree: Tree, name: string, projectRoot: string) {
	addProjectConfiguration(tree, name, {
		root: projectRoot,
		projectType: "application",
		sourceRoot: `${projectRoot}/src`,
		targets: {
			build: { command: "npm run build", options: { cwd: projectRoot } },
			serve: { command: "npm run start:dev", options: { cwd: projectRoot } },
			test: { command: "npm test", options: { cwd: projectRoot } },
		},
	});
}
