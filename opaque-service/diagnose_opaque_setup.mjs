import * as opaque from "@serenity-kit/opaque";

function describe(value) {
  if (typeof value === "string") return `string (length ${value.length})`;
  if (value instanceof Uint8Array) return `Uint8Array (length ${value.length})`;
  if (value === null) return "null";
  return typeof value;
}

try {
  console.log("[1/4] Importing OPAQUE...");
  console.log("Package import: OK");

  console.log("[2/4] Initializing WebAssembly...");
  await opaque.ready;
  console.log("WebAssembly: READY");

  console.log("[3/4] Generating server setup...");
  const setup = opaque.server.createSetup();
  console.log("Setup type:", describe(setup));

  if (typeof setup !== "string" || setup.length === 0) {
    throw new Error("createSetup() did not return a non-empty string");
  }

  console.log("[4/4] Validating server setup...");
  const publicKey = opaque.server.getPublicKey(setup);

  console.log("RESULT: SUCCESS");
  console.log("Setup length:", setup.length);
  console.log("Public key length:", publicKey.length);
  console.log("Secret values were not printed.");

} catch (error) {
  console.error("RESULT: FAILED");
  console.error("Error:", error.message);
  console.error(error.stack);
  process.exitCode = 1;
}