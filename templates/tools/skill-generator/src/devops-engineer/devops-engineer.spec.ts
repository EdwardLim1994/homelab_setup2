import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { devopsEngineerGenerator } from "./devops-engineer";

describe("devops-engineer generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the devops-engineer skills", async () => {
		await devopsEngineerGenerator(tree, {});
		expect(tree.exists(".opencode/skills/devops-engineer/SKILL.md")).toBe(true);
		expect(tree.children(".opencode/skills").length).toBeGreaterThan(1);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).length).toBeGreaterThan(0);
	});

	it("installs nothing when both flags are false", async () => {
		await devopsEngineerGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists("skills-lock.json")).toBe(false);
	});
});
