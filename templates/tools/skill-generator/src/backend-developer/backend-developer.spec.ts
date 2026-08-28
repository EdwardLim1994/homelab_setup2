import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { backendDeveloperGenerator } from "./backend-developer";

describe("backend-developer generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the backend-developer skills", async () => {
		await backendDeveloperGenerator(tree, {});
		expect(tree.exists(".opencode/skills/backend-developer/SKILL.md")).toBe(
			true,
		);
	});

	it("installs nothing when both flags are false", async () => {
		await backendDeveloperGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/backend-developer")).toBe(false);
	});
});
