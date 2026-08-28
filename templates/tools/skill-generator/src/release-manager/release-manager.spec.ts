import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { releaseManagerGenerator } from "./release-manager";

describe("release-manager generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the release-manager skills", async () => {
		await releaseManagerGenerator(tree, {});
		expect(tree.exists(".opencode/skills/release-manager/SKILL.md")).toBe(true);
	});

	it("installs nothing when both flags are false", async () => {
		await releaseManagerGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/release-manager")).toBe(false);
	});
});
