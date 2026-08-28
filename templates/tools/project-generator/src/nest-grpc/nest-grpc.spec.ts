import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { nestGrpcGenerator } from "./nest-grpc";
import type { NestGrpcGeneratorSchema } from "./schema";

// Runs the real Nest CLI (via `nest` or `npx @nestjs/cli`) - needs a network
// on first run and is slow. Bump the timeout accordingly.
describe("nest-grpc generator", () => {
	let tree: Tree;
	const options: NestGrpcGeneratorSchema = { name: "orders" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a NestJS project with gRPC wiring", async () => {
		await nestGrpcGenerator(tree, options);

		const config = readProjectConfiguration(tree, "orders");
		expect(config.root).toBe("apps/orders");
		expect(config.projectType).toBe("application");

		// nest new output landed
		expect(tree.exists("apps/orders/nest-cli.json")).toBe(true);
		expect(tree.exists("apps/orders/src/app.module.ts")).toBe(true);

		// gRPC overlay landed
		expect(tree.exists("apps/orders/proto/orders.proto")).toBe(true);
		const main = tree.read("apps/orders/src/main.ts", "utf-8") ?? "";
		expect(main).toContain("Transport.GRPC");
		expect(main).toContain("package: 'orders'");

		const pkg = JSON.parse(
			tree.read("apps/orders/package.json", "utf-8") ?? "{}",
		);
		expect(pkg.dependencies["@nestjs/microservices"]).toBeDefined();
		expect(pkg.dependencies["@grpc/grpc-js"]).toBeDefined();

		// per-service skill generated at the workspace root
		const skill =
			tree.read(".opencode/skills/orders-service/SKILL.md", "utf-8") ?? "";
		expect(skill).toContain("name: orders-service");

		// curated third-party skills copied verbatim under .opencode/skills
		expect(tree.exists(".opencode/skills/nestjs-expert/SKILL.md")).toBe(true);
		expect(
			tree.exists(".opencode/skills/typescript-pro/references/patterns.md"),
		).toBe(true);
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills)).toEqual(
			expect.arrayContaining(["sql-pro", "test-master"]),
		);
	}, 240_000);

	it("skips both skill kinds when disabled", async () => {
		await nestGrpcGenerator(tree, {
			name: "orders",
			skill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/orders-service/SKILL.md")).toBe(false);
		expect(tree.exists(".opencode/skills/nestjs-expert/SKILL.md")).toBe(false);
		expect(tree.exists("skills-lock.json")).toBe(false);
	}, 240_000);

	it("merges into an existing skills-lock.json", async () => {
		tree.write(
			"skills-lock.json",
			JSON.stringify({ version: 1, skills: { "my-skill": {} } }),
		);
		await nestGrpcGenerator(tree, { name: "orders", skill: false });
		const lock = JSON.parse(tree.read("skills-lock.json", "utf-8") ?? "{}");
		expect(Object.keys(lock.skills)).toEqual(
			expect.arrayContaining(["my-skill", "nestjs-expert"]),
		);
	}, 240_000);
});
