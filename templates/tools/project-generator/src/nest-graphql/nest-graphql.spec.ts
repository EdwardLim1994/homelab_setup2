import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { nestGraphqlGenerator } from "./nest-graphql";
import type { NestGraphqlGeneratorSchema } from "./schema";

// Runs the real Nest CLI (via `nest` or `npx @nestjs/cli`) - needs a network
// on first run and is slow. Bump the timeout accordingly.
describe("nest-graphql generator", () => {
	let tree: Tree;
	const options: NestGraphqlGeneratorSchema = { name: "catalog" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a NestJS code-first GraphQL server", async () => {
		await nestGraphqlGenerator(tree, options);

		const config = readProjectConfiguration(tree, "catalog");
		expect(config.root).toBe("apps/catalog");
		expect(config.projectType).toBe("application");

		// nest new output landed, REST controller removed, no proto
		expect(tree.exists("apps/catalog/nest-cli.json")).toBe(true);
		expect(tree.exists("apps/catalog/src/app.controller.ts")).toBe(false);
		expect(tree.exists("apps/catalog/proto")).toBe(false);

		// GraphQL overlay landed
		expect(tree.exists("apps/catalog/src/app.resolver.ts")).toBe(true);
		const mod = tree.read("apps/catalog/src/app.module.ts", "utf-8") ?? "";
		expect(mod).toContain("GraphQLModule.forRoot");
		expect(mod).toContain("ApolloDriver");
		const main = tree.read("apps/catalog/src/main.ts", "utf-8") ?? "";
		expect(main).not.toContain("Transport.GRPC");

		const pkg = JSON.parse(
			tree.read("apps/catalog/package.json", "utf-8") ?? "{}",
		);
		expect(pkg.dependencies["@nestjs/graphql"]).toBeDefined();
		expect(pkg.dependencies["@apollo/server"]).toBeDefined();
		expect(pkg.dependencies["@grpc/grpc-js"]).toBeUndefined();

		// per-service skill
		const skill =
			tree.read(".opencode/skills/catalog-service/SKILL.md", "utf-8") ?? "";
		expect(skill).toContain("name: catalog-service");
		expect(skill).toContain("GraphQL");

		// curated skills - no SQL ones
		expect(tree.exists(".opencode/skills/nestjs-expert/SKILL.md")).toBe(true);
		expect(tree.exists(".opencode/skills/typescript-pro/SKILL.md")).toBe(true);
		expect(tree.exists(".opencode/skills/sql-pro/SKILL.md")).toBe(false);
		expect(tree.exists(".opencode/skills/database-optimizer/SKILL.md")).toBe(
			false,
		);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills).sort()).toEqual([
			"debugging-wizard",
			"nestjs-expert",
			"test-master",
			"typescript-pro",
		]);
	}, 240_000);

	it("skips skills when disabled", async () => {
		await nestGraphqlGenerator(tree, {
			name: "catalog",
			skill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/catalog-service/SKILL.md")).toBe(
			false,
		);
		expect(tree.exists(".opencode/skills/nestjs-expert/SKILL.md")).toBe(false);
		expect(tree.exists("skills-lock.json")).toBe(false);
	}, 240_000);
});
