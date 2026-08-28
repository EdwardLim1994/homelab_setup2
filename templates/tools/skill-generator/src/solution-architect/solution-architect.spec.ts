import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { solutionArchitectGenerator } from "./solution-architect";

describe("solution-architect generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the solution-architect skills", async () => {
		await solutionArchitectGenerator(tree, {});
		expect(tree.exists(".opencode/skills/solution-architect/SKILL.md")).toBe(
			true,
		);
		expect(tree.children(".opencode/skills").length).toBeGreaterThan(1);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).length).toBeGreaterThan(0);
	});

	it("installs nothing when both flags are false", async () => {
		await solutionArchitectGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists("skills-lock.json")).toBe(false);
	});
});
