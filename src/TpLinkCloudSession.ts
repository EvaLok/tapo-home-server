import axios from "axios";

export class TpLinkCloudSession {
    public readonly token: string;
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
        this.token = params.token;
        this.termID = params.termID;
        this.appName = params.appName;
        this.appVer = params.appVer;
        this.ospf = params.ospf;
        this.netType = params.netType;
        this.locale = params.locale;
        this.userAgent = params.userAgent;
    }

    async getDevices(): Promise<Array<any>> {
        const request = {
            method: "POST",
            url: "https://wap.tplinkcloud.com",
            params: {
                appName: this.appName,
                termID: this.termID,
                appVer: this.appVer,
                ospf: this.ospf,
                netType: this.netType,
                locale: this.locale,
                token: this.token
            },
            headers: {
                "User-Agent": this.userAgent,
                "Content-Type": "application/json"
            },
            data: { method: "getDeviceList" }
        };

        const response = await axios(request);

        if( ! response.data || response.data.error_code !== 0 ){
            throw new Error(`Failed to fetch devices: ${response.data.error_code}`);
        }

        return response.data.result.deviceList;
    }
}

export interface ITpLinkCloudConstructorParams {
    token: string;
    termID: string;
    appName: string;
    appVer: string;
    ospf: string;
    netType: string;
    locale: string;
    userAgent: string;
}

export interface ITpLinkCloudProperties {
    termID?: string;
    appName?: string;
    appVer?: string;
    ospf?: string;
    netType?: string;
    locale?: string;
    userAgent?: string;
}
