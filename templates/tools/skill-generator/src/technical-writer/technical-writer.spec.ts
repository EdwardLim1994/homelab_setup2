import type { Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { technicalWriterGenerator } from "./technical-writer";

describe("technical-writer generator", () => {
	let tree: Tree;

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("installs the technical-writer skills", async () => {
		await technicalWriterGenerator(tree, {});
		expect(tree.children(".opencode/skills").length).toBeGreaterThan(1);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).length).toBeGreaterThan(0);
	});

	it("installs nothing when both flags are false", async () => {
		await technicalWriterGenerator(tree, {
			roleSkill: false,
			curatedSkills: false,
		});
		expect(tree.exists("skills-lock.json")).toBe(false);
	});
});
