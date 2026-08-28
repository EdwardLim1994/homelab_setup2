import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { nestRestGenerator } from "./nest-rest";
import type { NestRestGeneratorSchema } from "./schema";

// Runs the real Nest CLI (via `nest` or `npx @nestjs/cli`) - needs a network
// on first run and is slow. Bump the timeout accordingly.
describe("nest-rest generator", () => {
	let tree: Tree;
	const options: NestRestGeneratorSchema = { name: "accounts-api" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a stock NestJS REST API", async () => {
		await nestRestGenerator(tree, options);

		const config = readProjectConfiguration(tree, "accounts-api");
		expect(config.root).toBe("apps/accounts-api");
		expect(config.projectType).toBe("application");

		// stock scaffold, left as-is
		expect(tree.exists("apps/accounts-api/src/main.ts")).toBe(true);
		expect(tree.exists("apps/accounts-api/src/app.controller.ts")).toBe(true);
		expect(tree.exists("apps/accounts-api/src/app.service.ts")).toBe(true);

		// skills
		const skill =
			tree.read(".opencode/skills/accounts-api-service/SKILL.md", "utf-8") ??
			"";
		expect(skill).toContain("name: accounts-api-service");
		expect(tree.exists(".opencode/skills/nestjs-expert/SKILL.md")).toBe(true);
		expect(tree.exists(".opencode/skills/sql-pro/SKILL.md")).toBe(true);
		expect(tree.exists(".opencode/skills/test-master/SKILL.md")).toBe(true);
	}, 240_000);

	it("skips skills when disabled", async () => {
		await nestRestGenerator(tree, {
			name: "accounts-api",
			skill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/accounts-api-service/SKILL.md")).toBe(
			false,
		);
		expect(tree.exists("skills-lock.json")).toBe(false);
	}, 240_000);
});
