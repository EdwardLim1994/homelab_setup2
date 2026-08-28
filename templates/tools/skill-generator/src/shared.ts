import { existsSync, readdirSync, readFileSync } from "node:fs";
import * as path from "node:path";
import { type Tree, updateJson } from "@nx/devkit";

// opencode discovers skills from `.opencode/skills/<name>/SKILL.md`
const SKILL_ROOT = ".opencode/skills";

interface SkillsLock {
	version: number;
	skills: Record<string, unknown>;
}

export interface InstallSkillsOptions {
	/** Install the role's own `SKILL.md` (default true). */
	roleSkill?: boolean;
	/** Install the supporting skill pack under `files/curated-skills/` (default true). */
	curatedSkills?: boolean;
}

/** Copy every file from `srcDir` into the Tree under `destRoot`, verbatim. */
function copyDirIntoTree(tree: Tree, srcDir: string, destRoot: string) {
	for (const entry of readdirSync(srcDir, { withFileTypes: true })) {
		const abs = path.join(srcDir, entry.name);
		const rel = path.posix.join(destRoot, entry.name);
		if (entry.isDirectory()) {
			copyDirIntoTree(tree, abs, rel);
		} else {
			tree.write(rel, readFileSync(abs));
		}
	}
}

/** Merge the pack's `curated-skills-lock.json` into the workspace `skills-lock.json`. */
function mergeLock(tree: Tree, generatorDir: string) {
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
 * Install a role's skills into the target workspace, all under `.opencode/skills/`:
 * the role's own `SKILL.md` (as `.opencode/skills/<roleName>/SKILL.md`) and/or its
 * supporting pack from `files/curated-skills/` (merging `skills-lock.json`).
 * Both parts are skipped when absent, so this is safe for every role generator.
 */
export function installSkills(
	tree: Tree,
	generatorDir: string,
	roleName: string,
	options: InstallSkillsOptions = {},
) {
	const { roleSkill = true, curatedSkills = true } = options;

	const roleSkillFile = path.join(generatorDir, "SKILL.md");
	if (roleSkill && existsSync(roleSkillFile)) {
		tree.write(
			`${SKILL_ROOT}/${roleName}/SKILL.md`,
			readFileSync(roleSkillFile),
		);
	}

	const pack = path.join(generatorDir, "files/curated-skills");
	if (curatedSkills && existsSync(pack)) {
		copyDirIntoTree(tree, pack, SKILL_ROOT);
		mergeLock(tree, generatorDir);
	}
}
