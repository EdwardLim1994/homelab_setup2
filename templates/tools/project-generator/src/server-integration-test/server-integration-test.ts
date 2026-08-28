import * as path from "node:path";
import {
	addProjectConfiguration,
	formatFiles,
	generateFiles,
	names,
	type Tree,
} from "@nx/devkit";
import { addCuratedSkills } from "../shared";
import type { ServerIntegrationTestGeneratorSchema } from "./schema";

export async function serverIntegrationTestGenerator(
	tree: Tree,
	options: ServerIntegrationTestGeneratorSchema,
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

	// run-commands, not @nx/vitest:test - integration runs hit live services and
	// must not be cached.
	addProjectConfiguration(tree, n.fileName, {
		root: projectRoot,
		projectType: "application",
		sourceRoot: `${projectRoot}/src`,
		targets: {
			test: {
				command: "npx vitest run",
				options: { cwd: projectRoot },
			},
		},
	});

	await formatFiles(tree);
}

export default serverIntegrationTestGenerator;
