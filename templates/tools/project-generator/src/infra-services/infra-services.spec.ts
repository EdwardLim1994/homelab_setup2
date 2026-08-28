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
});
