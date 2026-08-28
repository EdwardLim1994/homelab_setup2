import * as path from "node:path";
import {
	addProjectConfiguration,
	formatFiles,
	generateFiles,
	names,
	type Tree,
} from "@nx/devkit";
import { addCuratedSkills } from "../shared";
import type { E2eTestGeneratorSchema } from "./schema";

export async function e2eTestGenerator(
	tree: Tree,
	options: E2eTestGeneratorSchema,
) {
	const n = names(options.name);
	const projectRoot = path.posix.join(options.directory ?? "apps", n.fileName);

	if (tree.exists(projectRoot)) {
		throw new Error(`${projectRoot} already exists`);
	}

	generateFiles(tree, path.join(__dirname, "files/project"), projectRoot, {
		...options,
		...n,
	});

	// bundled test skills, added to every generated project by default
	if (options.curatedSkills ?? true) {
		addCuratedSkills(tree, __dirname);
	}

	// run-commands, not a cached executor - e2e drives a live full stack.
	addProjectConfiguration(tree, n.fileName, {
		root: projectRoot,
		projectType: "application",
		sourceRoot: `${projectRoot}/tests`,
		targets: {
			e2e: {
				command: "npx playwright test",
				options: { cwd: projectRoot },
			},
		},
	});

	await formatFiles(tree);
}

export default e2eTestGenerator;
