import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";
import { e2eTestGenerator } from "./e2e-test";
import type { E2eTestGeneratorSchema } from "./schema";

describe("e2e-test generator", () => {
	let tree: Tree;
	const options: E2eTestGeneratorSchema = { name: "shop-e2e" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a headless Playwright e2e project", async () => {
		await e2eTestGenerator(tree, options);

		const config = readProjectConfiguration(tree, "shop-e2e");
		expect(config.root).toBe("apps/shop-e2e");
		expect(config.targets?.e2e?.command).toBe("npx playwright test");

		expect(tree.exists("apps/shop-e2e/playwright.config.ts")).toBe(true);
		expect(tree.exists("apps/shop-e2e/tests/shop-e2e.spec.ts")).toBe(true);

		const cfg = tree.read("apps/shop-e2e/playwright.config.ts", "utf-8") ?? "";
		expect(cfg).toContain("headless: true");
		expect(cfg).toContain("webServer:");

		// bundled skills land at the workspace root by default
		expect(tree.exists(".opencode/skills/playwright-expert/SKILL.md")).toBe(
			true,
		);
		expect(tree.exists(".opencode/skills/test-master/SKILL.md")).toBe(true);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).sort()).toEqual([
			"playwright-expert",
			"test-master",
		]);
	});

	it("skips skills when curatedSkills=false", async () => {
		await e2eTestGenerator(tree, { ...options, curatedSkills: false });
		expect(tree.exists(".opencode/skills/test-master/SKILL.md")).toBe(false);
		expect(tree.exists("skills-lock.json")).toBe(false);
	});

	it("refuses to overwrite an existing project", async () => {
		await e2eTestGenerator(tree, options);
		await expect(e2eTestGenerator(tree, options)).rejects.toThrow(
			/already exists/,
		);
	});
});
