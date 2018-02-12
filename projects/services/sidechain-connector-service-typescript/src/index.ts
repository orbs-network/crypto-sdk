import { config, ErrorHandler, grpc } from "orbs-core-library";
import { topology } from "orbs-core-library/src/common-library/topology";

import SidehainConnectorService from "./service";

ErrorHandler.setup();

const server = grpc.sidechainConnectorServer({
  endpoint: topology.endpoint,
  service: new SidehainConnectorService({
    ethereumNodeHttpAddress: config.get("ethereumNodeAddress")
  })
});
