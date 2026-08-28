import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { nestCronGenerator } from "./nest-cron";
import type { NestCronGeneratorSchema } from "./schema";

// Runs the real Nest CLI (via `nest` or `npx @nestjs/cli`) - needs a network
// on first run and is slow. Bump the timeout accordingly.
describe("nest-cron generator", () => {
	let tree: Tree;
	const options: NestCronGeneratorSchema = { name: "billing-jobs" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("scaffolds a NestJS scheduled-task worker", async () => {
		await nestCronGenerator(tree, options);

		const config = readProjectConfiguration(tree, "billing-jobs");
		expect(config.root).toBe("apps/billing-jobs");
		expect(config.projectType).toBe("application");

		// scaffold landed, HTTP controller removed
		expect(tree.exists("apps/billing-jobs/nest-cli.json")).toBe(true);
		expect(tree.exists("apps/billing-jobs/src/app.controller.ts")).toBe(false);

		// scheduler wiring
		expect(tree.exists("apps/billing-jobs/src/tasks.service.ts")).toBe(true);
		const mod = tree.read("apps/billing-jobs/src/app.module.ts", "utf-8") ?? "";
		expect(mod).toContain("ScheduleModule.forRoot()");
		const main = tree.read("apps/billing-jobs/src/main.ts", "utf-8") ?? "";
		expect(main).toContain("createApplicationContext");

		const pkg = JSON.parse(
			tree.read("apps/billing-jobs/package.json", "utf-8") ?? "{}",
		);
		expect(pkg.dependencies["@nestjs/schedule"]).toBeDefined();

		// skills
		const skill =
			tree.read(".opencode/skills/billing-jobs-service/SKILL.md", "utf-8") ??
			"";
		expect(skill).toContain("name: billing-jobs-service");
		expect(tree.exists(".opencode/skills/nestjs-expert/SKILL.md")).toBe(true);
		expect(tree.exists(".opencode/skills/sql-pro/SKILL.md")).toBe(true);
		expect(tree.exists(".opencode/skills/test-master/SKILL.md")).toBe(true);
	}, 240_000);

	it("skips skills when disabled", async () => {
		await nestCronGenerator(tree, {
			name: "billing-jobs",
			skill: false,
			curatedSkills: false,
		});
		expect(tree.exists(".opencode/skills/billing-jobs-service/SKILL.md")).toBe(
			false,
		);
		expect(tree.exists("skills-lock.json")).toBe(false);
	}, 240_000);
});
