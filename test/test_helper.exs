# Setup test environment
Application.put_env(:mox, :enable, true)

# Define mock
Mox.defmock(EcosystemManager.MockIOAdapter, for: EcosystemManager.CLI)

# Start ExUnit
ExUnit.start()
