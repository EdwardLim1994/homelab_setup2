import * as path from "node:path";
import { formatFiles, generateFiles, type Tree, updateJson } from "@nx/devkit";
import {
	addCuratedSkills,
	registerNestApp,
	scaffoldNestProject,
} from "../shared";
import type { NestGrpcGeneratorSchema } from "./schema";

// grpc runtime deps not shipped by `nest new`
const GRPC_DEPS = {
	"@grpc/grpc-js": "^1.12.6",
	"@grpc/proto-loader": "^0.7.13",
};

export async function nestGrpcGenerator(
	tree: Tree,
	options: NestGrpcGeneratorSchema,
) {
	const { names: n, projectRoot } = scaffoldNestProject(tree, options);

	const vars = { ...options, ...n, protoPackage: n.propertyName };

	// overlay the gRPC wiring (main.ts, controller, proto)
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

	// curated third-party skills relevant to a NestJS/gRPC/DB service
	if (options.curatedSkills ?? true) {
		addCuratedSkills(tree, __dirname);
	}

	// add grpc deps + pin @nestjs/microservices to the scaffold's nest version
	updateJson(tree, path.posix.join(projectRoot, "package.json"), (pkg) => {
		const nestVersion = pkg.dependencies?.["@nestjs/common"] ?? "^11.0.0";
		pkg.dependencies = {
			...pkg.dependencies,
			"@nestjs/microservices": nestVersion,
			...GRPC_DEPS,
		};
		return pkg;
	});

	// ship .proto files into the build output
	updateJson(tree, path.posix.join(projectRoot, "nest-cli.json"), (cfg) => {
		cfg.compilerOptions = cfg.compilerOptions ?? {};
		cfg.compilerOptions.assets = [
			...(cfg.compilerOptions.assets ?? []),
			{ include: "proto/**/*.proto", outDir: "dist" },
		];
		cfg.compilerOptions.watchAssets = true;
		return cfg;
	});

	registerNestApp(tree, n.fileName, projectRoot);
	await formatFiles(tree);
}

export default nestGrpcGenerator;
