import {
	addProjectConfiguration,
	formatFiles,
	generateFiles,
	type Tree,
} from "@nx/devkit";
import * as path from "path";
import type { InfraServicesGeneratorSchema } from "./schema";

export async function infraServicesGenerator(
	tree: Tree,
	options: InfraServicesGeneratorSchema,
) {
	const projectRoot = `libs/${options.name}`;
	addProjectConfiguration(tree, options.name, {
		root: projectRoot,
		projectType: "library",
		sourceRoot: `${projectRoot}/src`,
		targets: {},
	});
	generateFiles(tree, path.join(__dirname, "files"), projectRoot, options);
	await formatFiles(tree);
}

export default infraServicesGenerator;
