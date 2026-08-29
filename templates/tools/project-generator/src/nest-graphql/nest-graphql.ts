import * as path from "node:path";
import { generateFiles, type Tree, updateJson } from "@nx/devkit";
import {
	addCuratedSkills,
	registerNestApp,
	scaffoldNestProject,
} from "../shared";
import type { NestGraphqlGeneratorSchema } from "./schema";

// code-first GraphQL (Apollo) deps not shipped by `nest new`
const GRAPHQL_DEPS = {
	"@nestjs/apollo": "^13.0.0",
	"@nestjs/graphql": "^13.0.0",
	"@apollo/server": "^4.11.0",
	graphql: "^16.9.0",
};

export async function nestGraphqlGenerator(
	tree: Tree,
	options: NestGraphqlGeneratorSchema,
) {
	const { names: n, projectRoot } = scaffoldNestProject(tree, options);

	const vars = { ...options, ...n };

	// GraphQL is served over HTTP - the scaffold's REST controller is not needed
	tree.delete(path.posix.join(projectRoot, "src/app.controller.ts"));
	tree.delete(path.posix.join(projectRoot, "src/app.controller.spec.ts"));

	// overlay the GraphQL wiring (module, resolver, service, main)
	generateFiles(tree, path.join(__dirname, "files/app"), projectRoot, vars);

	// per-service skill: how to work on THIS service
	if (options.skill ?? true) {
		generateFiles(
			tree,
			path.join(__dirname, "files/service-skill"),
			`.opencode/skills/${n.fileName}-service`,
			vars,
		);
	}

	// curated third-party skills relevant to a NestJS/GraphQL service
	if (options.curatedSkills ?? true) {
		addCuratedSkills(tree, __dirname);
	}

	updateJson(tree, path.posix.join(projectRoot, "package.json"), (pkg) => {
		pkg.dependencies = { ...pkg.dependencies, ...GRAPHQL_DEPS };
		return pkg;
	});

	// the code-first schema is generated at runtime - don't commit it
	const gitignore = path.posix.join(projectRoot, ".gitignore");
	if (tree.exists(gitignore)) {
		const current = tree.read(gitignore, "utf-8") ?? "";
		if (!current.includes("src/schema.gql")) {
			tree.write(
				gitignore,
				`${current.trimEnd()}\n\n# generated GraphQL schema\nsrc/schema.gql\n`,
			);
		}
	}

	registerNestApp(tree, n.fileName, projectRoot);
}

export default nestGraphqlGenerator;
