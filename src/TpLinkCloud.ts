import { v4 } from "uuid";
import axios from "axios";
import {
    ITpLinkCloudProperties,
    TpLinkCloudSession
} from "./TpLinkCloudSession.js";

interface ITpLinkCloudConstructorParams {
    username: string;
    password: string;

}

export class TpLinkCloud {
    public readonly username: string;
    public readonly password: string;
    public readonly termID: string;
    public readonly appName: string;
    public readonly appVer: string;
    public readonly ospf: string;
    public readonly netType: string;
    public readonly locale: string;
    public readonly userAgent: string;

    constructor(
        params: ITpLinkCloudConstructorParams & ITpLinkCloudProperties
    ) {
        this.username = params.username;
        this.password = params.password;
        this.termID = params.termID ?? v4();
        this.appName = params.appName ?? "Kasa_Android";
        this.appVer = params.appVer ?? "1.4.4.607";
        this.ospf = params.ospf ?? "Android+6.0.1";
        this.netType = params.netType ?? "wifi";
        this.locale = params.locale ?? "en_US";
        this.userAgent = params.userAgent ?? "Dalvik/2.1.0 (Linux; U; Android 6.0.1; A0001 Build/M4B30X)";
    }

    async login(): Promise<TpLinkCloudSession> {
        const request = {
            method: "POST",
            url: "https://wap.tplinkcloud.com",
            params: {
                appName: this.appName,
                termID: this.termID,
                appVer: this.appVer,
                ospf: this.ospf,
                netType: this.netType,
                locale: this.locale
            },
            data: {
                method: "login",
                url: "https://wap.tplinkcloud.com",
                params: {
                    appType: this.appName,
                    cloudPassword: this.password,
                    cloudUserName: this.username,
                    terminalUUID: this.termID
                }
            },
            headers: {
                "User-Agent": this.userAgent,
                "Content-Type": "application/json"
            }
        };

        const response = await axios(request);

        if (!response.data || response.data.error_code !== 0) {
            throw new Error(`Login failed: ${response.data.error_code}`);
        }

        const token = response.data.result.token;

        return new TpLinkCloudSession({
            token: token,
            termID: this.termID,
            appName: this.appName,
            appVer: this.appVer,
            ospf: this.ospf,
            netType: this.netType,
            locale: this.locale,
            userAgent: this.userAgent
        });
    }
}
