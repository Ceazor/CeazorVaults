#here are some samples of a.deploy statements for the Vault and the BeethDual Strats.
name = CeazorVaultR.deploy(address _want, string  _name, string  _symbol, uint256 _approvalDelay, uint256 _depositFee {'from': accounts[0]})
cre8rBPTComp = StrategyBeethovenxDualToBeets.deploy()
        address _vault,             // ?????????????????????????????????????????? - ceazCRE8RF-Major
        address _input,             // 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83 - wFTM
        address _strategist,        // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _perFeeRecipient,   // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _want,              // 0xbb4607beDE4610e80d35C15692eFcB7807A2d0A6 - CRE8RFMajor BPT
        address _reward,            // 0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0 - CRE8R here
        address _rewarder           // 0x1098D1712592Bf4a3d73e5fD29Ae0da6554cd39f - CRE8R token farm
        uint256 _chefPoolId,        //39 CRE8R Gauge
        bytes32 _wantPoolId,        //0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140
        bytes32 _rewardPoolId,      //0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140 - this assumes the reward might be different than the want

#########
##START##
#########

#import the common variables

# vaults, strats, xCheese
ceazFBEETs = Contract("0x58E0ac1973F9d182058E6b63e7F4979bc333f493")
ceazFBeetsStrat = Contract("0x38a206688332674bE5eD20B5A65282224B43c189")
xCheeseFBeets = Contract("0xAe71E0AeADa3bf9a188f06464528313Ce8D3E740")

ceazCRE8RBPT = Contract("0xb06f1e0620f6b83c84a85E3c382442Cd1507F558")
ceazCRE8RBPTStrat = Contract("0xFE4bc4767d78A57d569cD68a9B1D6ddafd42bdc3")

# Common Tokens
wFTM = Contract("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")
cre8r = Contract("0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0")
fbeets = Contract("0xfcef8a994209d6916EB2C86cDD2AFD60Aa6F54b1")
beets = Contract("0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e")
cre8rBPT = Contract("0xbb4607beDE4610e80d35C15692eFcB7807A2d0A6")


#deploy this
ceazorVault2 = CeazorVaultR.deploy(cre8rBPT, "CeazorCre8rBPTVault", "ceazCRE8RBPT", 3600, 0, {'from': accounts[0]}, publish_source=True)
xCheeseTest = ExtraCheese.deploy(ceazFBEETs, cre8r, {'from': owner})
#Verify the at:

#1-Check that 1st entry matches vault above.
#2-If pool doesn't use wFTM you need to change this (This is untested)
#3-Assign address to recieve stratFee
#4-Assign address to recieve perFee
#5-This is the token that the vault takes in. the "want"
#6-This is the reward token of the pool, other than BEETS
#7-This is the seperate reward contract that brrs nonBEETS, ask devs, or harvest and find.
#8-This is the ID used in the Masterchef that links WANT to Beets rewards. (gauge number), ask or harvest to find.
#9-This is the poolID that swaps the want, found in READ of the want
#10-This is the poolID that swaps the reward, CHECK if REWARDS don't match WANT 
cre8rBPTComp2 = BPTCompounderToBeets.deploy(
    "0xb06f1e0620f6b83c84a85E3c382442Cd1507F558",    
    "0x3c5Aac016EF2F178e8699D6208796A2D67557fe2",  
    "0x3c5Aac016EF2F178e8699D6208796A2D67557fe2",
    "0xbb4607beDE4610e80d35C15692eFcB7807A2d0A6",
    "0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0",
    "0x1098D1712592Bf4a3d73e5fD29Ae0da6554cd39f",
    39,
    "0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140",
    "0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140",    
    {'from': accounts[0]})

#Get the Strategy address outputted and use it to init the vault. DO this once.
ceazorVault.initialize(ceazCRE8RBPTStrat, {'from': accounts[0]})

#Deploy XCheese for strategy.
#Needs stake token, reward token, duration
extraCheese = ExtraCheese.deploy(ceazorVault, beets, 1209600, {'from': accounts[0]})

#Transfer ownerships of all three to owner.
ceazorVault.transferOwnership(owner, {'from': accounts[0]})
cre8rBPTComp.transferOwnership(owner, {'from': accounts[0]})
xCheese.transferOwnership(owner, {'from': accounts[0]})


######
#TEST#
######

cre8rBPT.approve(ceazorVault, 11*1e18, {'from': ceazor})
ceazorVault.depositAll({'from': ceazor})
ceazorVault.balanceOf(ceazor)
chain.mine(4000)
tx = cre8rBPTComp.harvest({'from': owner})
tx.call_trace(True)

##VERIFY
CeazorVaultR.publish_source(Contract('0xb06f1e0620f6b83c84a85E3c382442Cd1507F558'))
