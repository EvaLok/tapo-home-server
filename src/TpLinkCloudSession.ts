
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
