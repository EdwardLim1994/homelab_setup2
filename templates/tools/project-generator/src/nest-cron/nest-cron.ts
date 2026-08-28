import * as path from "node:path";
import { formatFiles, generateFiles, type Tree, updateJson } from "@nx/devkit";
import {
	addCuratedSkills,
	registerNestApp,
	scaffoldNestProject,
} from "../shared";
import type { NestCronGeneratorSchema } from "./schema";

// task-scheduler dep not shipped by `nest new` (bundles `cron` internally)
const SCHEDULE_DEPS = {
	"@nestjs/schedule": "^6.0.0",
};

export async function nestCronGenerator(
	tree: Tree,
	options: NestCronGeneratorSchema,
) {
	const { names: n, projectRoot } = scaffoldNestProject(tree, options);

	const vars = { ...options, ...n };

	// headless worker - drop the scaffold's HTTP controller/service
	for (const f of [
		"src/app.controller.ts",
		"src/app.controller.spec.ts",
		"src/app.service.ts",
	]) {
		tree.delete(path.posix.join(projectRoot, f));
	}

	// overlay the scheduler wiring (module, tasks service, main)
	generateFiles(tree, path.join(__dirname, "files/app"), projectRoot, vars);

	// per-service skill: how to work on THIS worker
	if (options.skill ?? true) {
		generateFiles(
			tree,
			path.join(__dirname, "files/service-skill"),
			`.opencode/skills/${n.fileName}-service`,
			vars,
		);
	}

	// curated third-party skills relevant to a NestJS service
	if (options.curatedSkills ?? true) {
		addCuratedSkills(tree, __dirname);
	}

	updateJson(tree, path.posix.join(projectRoot, "package.json"), (pkg) => {
		pkg.dependencies = { ...pkg.dependencies, ...SCHEDULE_DEPS };
		return pkg;
	});

	registerNestApp(tree, n.fileName, projectRoot);
	await formatFiles(tree);
}

export default nestCronGenerator;
