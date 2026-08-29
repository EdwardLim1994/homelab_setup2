import * as path from "node:path";
import {
	addProjectConfiguration,
	generateFiles,
	names,
	type Tree,
} from "@nx/devkit";
import { addCuratedSkills } from "../shared";
import type { WebIntegrationTestGeneratorSchema } from "./schema";

export async function webIntegrationTestGenerator(
	tree: Tree,
	options: WebIntegrationTestGeneratorSchema,
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

	// run-commands, not a cached executor - browser tests hit live sites.
	addProjectConfiguration(tree, n.fileName, {
		root: projectRoot,
		projectType: "application",
		sourceRoot: `${projectRoot}/tests`,
		targets: {
			test: {
				command: "npx playwright test",
				options: { cwd: projectRoot },
			},
		},
	});
}

export default webIntegrationTestGenerator;
