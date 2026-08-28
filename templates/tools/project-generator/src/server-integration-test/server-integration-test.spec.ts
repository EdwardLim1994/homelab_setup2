import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";
import type { ServerIntegrationTestGeneratorSchema } from "./schema";
import { serverIntegrationTestGenerator } from "./server-integration-test";

describe("server-integration-test generator", () => {
	let tree: Tree;
	const options: ServerIntegrationTestGeneratorSchema = { name: "orders-api" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a vitest integration test project", async () => {
		await serverIntegrationTestGenerator(tree, options);

		const config = readProjectConfiguration(tree, "orders-api");
		expect(config.root).toBe("apps/orders-api");
		expect(config.targets?.test?.command).toBe("npx vitest run");

		expect(tree.exists("apps/orders-api/vitest.config.ts")).toBe(true);
		expect(tree.exists("apps/orders-api/src/api-client.ts")).toBe(true);
		expect(tree.exists("apps/orders-api/tests/setup.ts")).toBe(true);
		expect(tree.exists("apps/orders-api/tests/orders-api.spec.ts")).toBe(true);
		expect(tree.exists("apps/orders-api/.env.example")).toBe(true);

		const spec =
			tree.read("apps/orders-api/tests/orders-api.spec.ts", "utf-8") ?? "";
		expect(spec).toContain("OrdersApi API integration");

		// bundled test skill lands under .opencode/skills by default
		expect(tree.exists(".opencode/skills/test-master/SKILL.md")).toBe(true);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills)).toContain("test-master");
	});

	it("skips skills when curatedSkills=false", async () => {
		await serverIntegrationTestGenerator(tree, {
			...options,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/test-master/SKILL.md")).toBe(false);
		expect(tree.exists("skills-lock.json")).toBe(false);
	});

	it("refuses to overwrite an existing project", async () => {
		await serverIntegrationTestGenerator(tree, options);
		await expect(serverIntegrationTestGenerator(tree, options)).rejects.toThrow(
			/already exists/,
		);
	});
});
