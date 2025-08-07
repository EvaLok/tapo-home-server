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

            Assert.isString(result);

        });
    });
});
