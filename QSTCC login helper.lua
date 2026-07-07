--[=====[
[[SND Metadata]]
author: Friendly
version: 1.0.0
description: >-
  Login helper to QST Companion Companion

  (prevent getting stuck on Character Select screen)
triggers:
- onlogout

[[End Metadata]]
--]=====]
yield('/wait 5.036')
while not Addons.GetAddon("_DTR").Exists do -- prevent stuck on charaselect
    yield('/wait 10.037')
    if Addons.GetAddon("CharaSelect").Exists and not Addons.GetAddon("SelectOK").Exists then
        yield('/wait 10.038')
        if Addons.GetAddon("CharaSelect").Exists and not Addons.GetAddon("SelectOK").Exists then --!could be replaced with a callback
            yield('/send DECIMAL')
            yield('/send DECIMAL')
            yield('/wait 10.039')
            yield('/send NUMPAD0')
        end
    end
end