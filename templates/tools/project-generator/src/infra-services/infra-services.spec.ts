import { readProjectConfiguration, type Tree } from "@nx/devkit";
import { createTreeWithEmptyWorkspace } from "@nx/devkit/testing";

import { infraServicesGenerator } from "./infra-services";
import type { InfraServicesGeneratorSchema } from "./schema";

describe("infra-services generator", () => {
	let tree: Tree;
	const options: InfraServicesGeneratorSchema = { name: "test" };

	beforeEach(() => {
		tree = createTreeWithEmptyWorkspace();
	});

	it("should run successfully", async () => {
		await infraServicesGenerator(tree, options);
		const config = readProjectConfiguration(tree, "test");
		expect(config).toBeDefined();
	});

	it("emits the bundled services tree, including the terraform config and helm charts", async () => {
		await infraServicesGenerator(tree, options);
		// generateFiles ran over every bundled file without an EJS parse error
		expect(tree.exists("libs/test/src/services/terraform/main.tf")).toBe(true);
		expect(tree.exists("libs/test/src/services/authentik/helm/Chart.yaml")).toBe(true);
		// runtime artifacts must never ship in the scaffold
		expect(tree.exists("libs/test/src/services/terraform/.terraform")).toBe(false);
		expect(
			tree.exists("libs/test/src/services/terraform/terraform.tfstate.d"),
		).toBe(false);
	});
});
