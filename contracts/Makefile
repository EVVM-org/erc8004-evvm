.PHONY: deployUserValidatorManual deployUserValidator deployUserValidatorPreRegistrated
include .env
export 

DEPLOY_ARGS :=  --rpc-url $(RPC_URL) \
				--account defaultKey \
				--broadcast \
				--verify \
				--etherscan-api-key $(ETHERSCAN_API)

deployUserValidatorManual:
	@forge clean
	@echo "Deploying UserValidatorManual to testnet"
	@forge script script/DeployUserValidatorManual.s.sol:DeployUserValidatorManual $(DEPLOY_ARGS)

deployUserValidator:
	@forge clean
	@echo "Deploying UserValidator to testnet"
	@forge script script/DeployUserValidator.s.sol:DeployUserValidator $(DEPLOY_ARGS)

deployUserValidatorPreRegistrated:
	@forge clean
	@echo "Deploying UserValidatorPreRegistrated to testnet"
	@forge script script/DeployUserValidatorPreRegistrated.s.sol:DeployUserValidatorPreRegistrated $(DEPLOY_ARGS)
