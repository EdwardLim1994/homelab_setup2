import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";
import type { WebIntegrationTestGeneratorSchema } from "./schema";
import { webIntegrationTestGenerator } from "./web-integration-test";

describe("web-integration-test generator", () => {
	let tree: Tree;
	const options: WebIntegrationTestGeneratorSchema = { name: "storefront-web" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a headless Playwright project", async () => {
		await webIntegrationTestGenerator(tree, options);

		const config = readProjectConfiguration(tree, "storefront-web");
		expect(config.root).toBe("apps/storefront-web");
		expect(config.targets?.test?.command).toBe("npx playwright test");

		expect(tree.exists("apps/storefront-web/playwright.config.ts")).toBe(true);
		expect(
			tree.exists("apps/storefront-web/tests/storefront-web.spec.ts"),
		).toBe(true);
		expect(tree.exists("apps/storefront-web/.env.example")).toBe(true);

		const cfg =
			tree.read("apps/storefront-web/playwright.config.ts", "utf-8") ?? "";
		expect(cfg).toContain("headless: true");

		const pkg = JSON.parse(
			tree.read("apps/storefront-web/package.json", "utf-8") ?? "{}",
		);
		expect(pkg.devDependencies["@playwright/test"]).toBeDefined();

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
		await webIntegrationTestGenerator(tree, {
			...options,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/playwright-expert/SKILL.md")).toBe(
			false,
		);
		expect(tree.exists("skills-lock.json")).toBe(false);
	});

	it("refuses to overwrite an existing project", async () => {
		await webIntegrationTestGenerator(tree, options);
		await expect(webIntegrationTestGenerator(tree, options)).rejects.toThrow(
			/already exists/,
		);
	});
});
