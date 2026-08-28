import * as path from "node:path";
import { formatFiles, generateFiles, type Tree } from "@nx/devkit";
import {
	addCuratedSkills,
	registerNestApp,
	scaffoldNestProject,
} from "../shared";
import type { NestRestGeneratorSchema } from "./schema";

export async function nestRestGenerator(
	tree: Tree,
	options: NestRestGeneratorSchema,
) {
	// stock `nest new` - a REST API out of the box, no overlay
	const { names: n, projectRoot } = scaffoldNestProject(tree, options);

	const vars = { ...options, ...n };

	if (options.skill ?? true) {
		generateFiles(
			tree,
			path.join(__dirname, "files/service-skill"),
			`.opencode/skills/${n.fileName}-service`,
			vars,
		);
	}

	if (options.curatedSkills ?? true) {
		addCuratedSkills(tree, __dirname);
	}

	registerNestApp(tree, n.fileName, projectRoot);
	await formatFiles(tree);
}

export default nestRestGenerator;
