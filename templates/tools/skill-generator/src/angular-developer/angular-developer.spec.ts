import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { angularDeveloperGenerator } from "./angular-developer";

describe("angular-developer generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the angular-developer skills", async () => {
		await angularDeveloperGenerator(tree, {});
		expect(tree.children(".opencode/skills").length).toBeGreaterThan(1);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).length).toBeGreaterThan(0);
	});

	it("installs nothing when both flags are false", async () => {
		await angularDeveloperGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists("skills-lock.json")).toBe(false);
	});
});
