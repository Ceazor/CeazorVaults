

#########
##START##
#########

#import the common variables

# vaults, strats, xCheese
ceazFBEETs = Contract("0x58E0ac1973F9d182058E6b63e7F4979bc333f493")
ceazFBeetsStrat = Contract("0x38a206688332674bE5eD20B5A65282224B43c189")
xCheeseFBeets = Contract("0xAe71E0AeADa3bf9a188f06464528313Ce8D3E740")

ceazCRE8RBPT = Contract("0xC93dd4F61C4598192f6c150Af38a58514eB3abbe")
cre8rBPTComp = Contract("0xc1374494d47Eb254e6Aa58ef2BfffA81D6317B23")
xCheeseCre8r = Contract("0x6d9cCA043f7De62646e810FA19a4386c1588C02c")

# Common Tokens
wFTM = Contract("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83")
cre8r = Contract("0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0")
fbeets = Contract("0xfcef8a994209d6916EB2C86cDD2AFD60Aa6F54b1")
beets = Contract("0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e")
cre8rBPT = Contract("0xbb4607beDE4610e80d35C15692eFcB7807A2d0A6")


#deploy this
ceazCRE8RBPT = CeazorVaultR.deploy(
    cre8rBPT, 
    "CeazorCre8rBPTVault", 
    "ceazCRE8RBPT",
     0, 
     {'from': accounts[0]}, publish_source=True)

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
cre8rBPTComp = BPTCompounderToBeets.deploy(
    "0xC93dd4F61C4598192f6c150Af38a58514eB3abbe",    
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
extraCheese = ExtraCheese.deploy(ceazorVault, beets, 1209600, {'from': accounts[0]}, publish_source=True)

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
