import * as path from "node:path";
import { addProjectConfiguration, generateFiles, type Tree } from "@nx/devkit";
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
}

export default infraServicesGenerator;
