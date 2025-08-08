import { assert as Assert } from "chai";
import { TpLinkCloud } from "../../src/TpLinkCloud.js";
import * as dotenv from "dotenv";
dotenv.config();

describe(`TpLinkCloud`, function () {

    const sut = TpLinkCloud;

    describe(`login`, function(){
        it(`should login and be able to display devices with valid credentials`, async function () {
            const cloud = new sut({
                username: process.env.TPLINK_CLOUD_USERNAME || "user not set",
                password: process.env.TPLINK_CLOUD_PASSWORD || "pass not set",
            });

            const session = await cloud.login();

            Assert.isObject(session, "Login should return a session object");
            Assert.isString(session.token, "Session token should be a string");
            Assert.equal(cloud.termID, session.termID, "TermID should match the one used in login");
            Assert.equal(cloud.appName, session.appName, "AppName should match the one used in login");
            Assert.equal(cloud.appVer, session.appVer, "AppVer should match the one used in login");
            Assert.equal(cloud.ospf, session.ospf, "OSPF should match the one used in login");
            Assert.equal(cloud.netType, session.netType, "NetType should match the one used in login");
            Assert.equal(cloud.locale, session.locale, "Locale should match the one used in login");
            Assert.equal(cloud.userAgent, session.userAgent, "UserAgent should match the one used in login");

            // get device list
            const devices = await session.getDeviceList();

            Assert.isArray(devices);

            const p306 = devices.find(device => device.deviceName === "P306");
            Assert.isDefined(p306, "P306 device should be found in the device list");


            // get device info
            const deviceInfo = await session.getDeviceInfo(p306);

            Assert.isObject(deviceInfo, "Device info should be an object");


        });
    });
});
