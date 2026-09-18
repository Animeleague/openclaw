# Banked live deployment script exists as conversation artifact:
# Deploy-ForgeRoomContextDirtyTurnV8.ps1
#
# V8 design:
# - no Forge room chronology in turn/start.additionalContext
# - bounded room block is prepended to the disposable native user turn
# - existing rollback / clean-reinject transaction removes dirty room input
# - non-room Forge runtime context remains in developer instructions
# - release only after live Sol/Luna cache/staircase audit passes
