import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { frontendDeveloperGenerator } from "./frontend-developer";

describe("frontend-developer generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the frontend-developer skills", async () => {
		await frontendDeveloperGenerator(tree, {});
		expect(tree.exists(".opencode/skills/frontend-developer/SKILL.md")).toBe(
			true,
		);
	});

	it("installs nothing when both flags are false", async () => {
		await frontendDeveloperGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/frontend-developer")).toBe(false);
	});
});
