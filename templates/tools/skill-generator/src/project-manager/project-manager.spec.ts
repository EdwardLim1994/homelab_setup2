import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { projectManagerGenerator } from "./project-manager";

describe("project-manager generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the project-manager skills", async () => {
		await projectManagerGenerator(tree, {});
		expect(tree.exists(".opencode/skills/project-manager/SKILL.md")).toBe(true);
	});

	it("installs nothing when both flags are false", async () => {
		await projectManagerGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/project-manager")).toBe(false);
	});
});
