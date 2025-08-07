import { assert as Assert } from "chai";
import { TpLinkCloud } from "../../src/TpLinkCloud.js";
import * as dotenv from "dotenv";
dotenv.config();

describe(`TpLinkCloud`, function () {

    const sut = TpLinkCloud;

    describe(`login`, function(){
        it(`should login with valid credentials`, async function () {
            const cloud = new sut({
                username: process.env.TPLINK_CLOUD_USERNAME || "user not set",
                password: process.env.TPLINK_CLOUD_PASSWORD || "pass not set",
            });

            const result = await cloud.login();

            Assert.isObject(result, "Login should return a session object");
            Assert.isString(result.token, "Session token should be a string");
            Assert.equal(cloud.termID, result.termID, "TermID should match the one used in login");
            Assert.equal(cloud.appName, result.appName, "AppName should match the one used in login");
            Assert.equal(cloud.appVer, result.appVer, "AppVer should match the one used in login");
            Assert.equal(cloud.ospf, result.ospf, "OSPF should match the one used in login");
            Assert.equal(cloud.netType, result.netType, "NetType should match the one used in login");
            Assert.equal(cloud.locale, result.locale, "Locale should match the one used in login");
            Assert.equal(cloud.userAgent, result.userAgent, "UserAgent should match the one used in login");

        });
    });
});
