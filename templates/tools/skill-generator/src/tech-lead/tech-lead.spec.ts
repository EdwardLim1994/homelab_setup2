import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { techLeadGenerator } from "./tech-lead";

describe("tech-lead generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the tech-lead skills", async () => {
		await techLeadGenerator(tree, {});
		expect(tree.exists(".opencode/skills/tech-lead/SKILL.md")).toBe(true);
		expect(tree.children(".opencode/skills").length).toBeGreaterThan(1);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).length).toBeGreaterThan(0);
	});

	it("installs nothing when both flags are false", async () => {
		await techLeadGenerator(tree, { roleSkill: false, curatedSkills: false });
		expect(tree.exists("skills-lock.json")).toBe(false);
	});
});
