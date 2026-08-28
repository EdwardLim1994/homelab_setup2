import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { productOwnerGenerator } from "./product-owner";

describe("product-owner generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the product-owner skills", async () => {
		await productOwnerGenerator(tree, {});
		expect(tree.exists(".opencode/skills/product-owner/SKILL.md")).toBe(true);
	});

	it("installs nothing when both flags are false", async () => {
		await productOwnerGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/product-owner")).toBe(false);
	});
});
