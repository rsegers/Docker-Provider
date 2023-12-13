import { CertificateManager, WebhookCertData } from '../CertificateGenerator.js';
import * as k8s from '@kubernetes/client-node';
import forge from 'node-forge';

describe('CertificateManager', () => {
    let kubeConfig: k8s.KubeConfig;

    beforeEach(() => {
        kubeConfig = new k8s.KubeConfig();
        jest.clearAllMocks();
        jest.resetAllMocks();
        // Set up kubeConfig with necessary configurations
    });

    describe('CreateWebhookAndCertificates', () => {
        it('should create and patch webhook and certificates', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            const createOrUpdateCertificates = jest.spyOn(CertificateManager as any, 'CreateOrUpdateCertificates').mockReturnValue({
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsKey: 'mockTLSKey',
                tlsCert: 'mockTLSCert',
            } as WebhookCertData);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.CreateWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(createOrUpdateCertificates).toHaveBeenCalledWith(operationId);
            expect(patchWebhookAndCertificates).toHaveBeenCalledWith(operationId, mockKubeConfig, {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsKey: 'mockTLSKey',
                tlsCert: 'mockTLSCert',
            } as WebhookCertData, mockClusterArmId, mockClusterArmRegion);
        });
    });

    describe('ReconcileWebhookAndCertificates', () => {
        it('should reconcile webhook and certificates - happy path', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            const secretObj: WebhookCertData = (CertificateManager as any).CreateOrUpdateCertificates('test-operationId');
            jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockResolvedValue(secretObj);
            const getMutatingWebhookCABundle = jest.spyOn(CertificateManager as any, 'GetMutatingWebhookCABundle').mockResolvedValue(secretObj.caCert);
            jest.spyOn(CertificateManager as any, 'isCertificateSignedByCA').mockReturnValue(true);
            const isValidCertificate = jest.spyOn(CertificateManager as any, 'IsValidCertificate').mockReturnValue(true);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockResolvedValue(null);
            const restartWebhookReplicaset = jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.ReconcileWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(isValidCertificate).toHaveBeenCalledWith(operationId, secretObj.caCert, secretObj, mockClusterArmId, mockClusterArmRegion);
            expect(getMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(patchWebhookAndCertificates).not.toBeCalled();
            expect(restartWebhookReplicaset).not.toBeCalled();
        });

        it('should reconcile webhook and certificates - invalid certificate in secret store and/or mwhc', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockResolvedValue(null);
            const getMutatingWebhookCABundle = jest.spyOn(CertificateManager as any, 'GetMutatingWebhookCABundle').mockResolvedValue(null);
            const getSecretDetails =  jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockResolvedValue(null);
            jest.spyOn(CertificateManager as any, 'isCertificateSignedByCA').mockReturnValue(false);
            const isValidCertificate = jest.spyOn(CertificateManager as any, 'IsValidCertificate').mockReturnValue(false);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockResolvedValue(null);
            const restartWebhookReplicaset = jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.ReconcileWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(isValidCertificate).toHaveBeenCalledWith(operationId, null, null, mockClusterArmId, mockClusterArmRegion);
            expect(getMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(getSecretDetails).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(patchWebhookAndCertificates).not.toBeCalled();
            expect(restartWebhookReplicaset).not.toBeCalled();
        });

        it('should generate all new certs for host and CA if certs are corrupted or mismatched', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            const mockCertData: WebhookCertData = {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsCert: 'mockTLSCert',
                tlsKey: 'mockTLSKey'
            };
            const createOrUpdateCertificates = jest.spyOn(CertificateManager as any, 'CreateOrUpdateCertificates').mockReturnValue({
                caCert: mockCertData.caCert,
                caKey: mockCertData.caKey,
                tlsKey: mockCertData.tlsKey,
                tlsCert: mockCertData.tlsCert
            } as WebhookCertData);
            jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockImplementation((operationId: string, kubeConfig: k8s.KubeConfig) => {
                if (!kubeConfig) {
                    throw new Error('Invalid KubeConfig');
                }
                return new Promise((resolve) => {
                    resolve(mockCertData);
                });
            });
            const getMutatingWebhookCABundle = jest.spyOn(CertificateManager as any, 'GetMutatingWebhookCABundle').mockResolvedValue(mockCertData.caCert);
            jest.spyOn(CertificateManager as any, 'isCertificateSignedByCA').mockReturnValue(false);
            const isValidCertificate = jest.spyOn(CertificateManager as any, 'IsValidCertificate').mockReturnValue(true);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockImplementation((_1: string, kc: k8s.KubeConfig, certificates: WebhookCertData, _2: string, _3: string) => {
                if (!(kc && certificates && certificates.caCert && certificates.caKey && certificates.tlsCert && certificates.tlsKey 
                        && forge.pki.certificateFromPem(certificates.caCert) && forge.pki.privateKeyFromPem(certificates.caKey) && forge.pki.certificateFromPem(certificates.tlsCert) && forge.pki.privateKeyFromPem(certificates.tlsKey))) {
                        throw new Error('Invalid KubeConfig or Certificates');
                }
                return null;
            });
            const restartWebhookReplicaset = jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockImplementation((_1: string, kc: k8s.KubeConfig, _2: string, _3: string) => {
                if (!kc) {
                    throw new Error('Invalid KubeConfig');
                }
                return null;
            });

            const operationId = 'operationId';
            await CertificateManager.ReconcileWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            //Assert
            expect(isValidCertificate).toHaveBeenCalledWith(operationId, mockCertData.caCert, mockCertData, mockClusterArmId, mockClusterArmRegion);
            expect(createOrUpdateCertificates).toHaveBeenLastCalledWith(operationId);
            expect(getMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(patchWebhookAndCertificates).toHaveBeenCalledWith(operationId, mockKubeConfig, mockCertData, mockClusterArmId, mockClusterArmRegion);
            expect(restartWebhookReplicaset).toHaveBeenCalledWith(operationId, mockKubeConfig, mockClusterArmId, mockClusterArmRegion);
        });

        it('should handle only CA cert expiration', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            jest.spyOn(Date, 'now').mockReturnValueOnce(0).mockReturnValue(800 * 24 * 60 * 60 * 1000);
            const realCertObj: WebhookCertData = (CertificateManager as any).CreateOrUpdateCertificates('test-operationId');
            const caCertDecoded: forge.pki.Certificate = forge.pki.certificateFromPem(realCertObj.caCert);
            const getSecretDetails =  jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockImplementation((operationId: string, kubeConfig: k8s.KubeConfig) => {
                if (!kubeConfig) {
                    throw new Error('Invalid KubeConfig');
                }
                return new Promise((resolve) => {
                    resolve(realCertObj);
                });
            });
            const getMutatingWebhookCABundle = jest.spyOn(CertificateManager as any, 'GetMutatingWebhookCABundle').mockImplementation((operationId: string, kubeConfig: k8s.KubeConfig) => {
                if (!kubeConfig) {
                    throw new Error('Invalid KubeConfig');
                }
                return new Promise((resolve) => {
                    resolve(realCertObj.caCert);
                });
            });
            const generateCACertificate = jest.spyOn(CertificateManager as any, 'GenerateCACertificate').mockImplementation((existingKeyPair?: forge.pki.rsa.KeyPair) => {
                if (existingKeyPair && existingKeyPair.privateKey && forge.pki.privateKeyToPem(existingKeyPair.privateKey) && existingKeyPair.publicKey && forge.pki.publicKeyToPem(existingKeyPair.publicKey)) {
                    return caCertDecoded;
                }
                throw new Error('Invalid CA Private Key and/or Public key');

            });
            jest.spyOn(CertificateManager as any, 'isCertificateSignedByCA').mockReturnValue(true);
            const isValidCertificate = jest.spyOn(CertificateManager as any, 'IsValidCertificate').mockReturnValue(true);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockImplementation((_1: string, kc: k8s.KubeConfig, certificates: WebhookCertData, _2: string, _3: string) => {
                if (!(kc && certificates && certificates.caCert && certificates.caKey && certificates.tlsCert && certificates.tlsKey 
                        && forge.pki.certificateFromPem(certificates.caCert) && forge.pki.privateKeyFromPem(certificates.caKey) && forge.pki.certificateFromPem(certificates.tlsCert) && forge.pki.privateKeyFromPem(certificates.tlsKey))) {
                        throw new Error('Invalid KubeConfig or Certificates');
                }
                return null;
            });
            const restartWebhookReplicaset = jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.ReconcileWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(isValidCertificate).toHaveBeenCalledWith(operationId, realCertObj.caCert, realCertObj, mockClusterArmId, mockClusterArmRegion);
            expect(getMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(getSecretDetails).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(generateCACertificate).toHaveBeenCalled();
            expect(patchWebhookAndCertificates).toHaveBeenCalled();
            expect(restartWebhookReplicaset).not.toBeCalled();
        });

        it('should handle only Host cert expiration', async () => {
            const mockKubeConfig = new k8s.KubeConfig();
            const mockClusterArmId = 'clusterArmId';
            const mockClusterArmRegion = 'clusterArmRegion';
            jest.spyOn(k8s.KubeConfig.prototype, 'loadFromDefault').mockReturnValue(null);
            jest.spyOn(Date, 'now').mockReturnValueOnce(800 * 24 * 60 * 60 * 1000).mockReturnValueOnce(0).mockReturnValue(800 * 24 * 60 * 60 * 1000);
            const realCertObj: WebhookCertData = (CertificateManager as any).CreateOrUpdateCertificates('test-operationId');
            const hostCertDecoded: forge.pki.Certificate = forge.pki.certificateFromPem(realCertObj.tlsCert);
            realCertObj.caCert = null;
            hostCertDecoded.privateKey = forge.pki.privateKeyFromPem(realCertObj.tlsKey);
            const getSecretDetails =  jest.spyOn(CertificateManager as any, 'GetSecretDetails').mockResolvedValue(realCertObj);
            const getMutatingWebhookCABundle = jest.spyOn(CertificateManager as any, 'GetMutatingWebhookCABundle').mockImplementation((_: string, kubeConfig: k8s.KubeConfig) => {
                if (!kubeConfig) {
                    throw new Error('Invalid KubeConfig');
                }
                return new Promise((resolve) => {
                    resolve(realCertObj.caCert);
                });
            });
            const generateHostCertificate = jest.spyOn(CertificateManager as any, 'GenerateHostCertificate').mockImplementation((caCert: forge.pki.Certificate) => {
                if (!(caCert && caCert.privateKey && forge.pki.privateKeyToPem(caCert.privateKey))) {
                    throw new Error('Invalid CA Certificate or CA Private Key');
                }
                return hostCertDecoded;
            });
            jest.spyOn(CertificateManager as any, 'isCertificateSignedByCA').mockReturnValue(true);
            const isValidCertificate = jest.spyOn(CertificateManager as any, 'IsValidCertificate').mockReturnValue(true);
            const patchWebhookAndCertificates = jest.spyOn(CertificateManager as any, 'PatchWebhookAndCertificates').mockImplementation((_1: string, kc: k8s.KubeConfig, certificates: WebhookCertData, _2: string, _3: string) => {
                if (!(kc && certificates && certificates.caCert && certificates.caKey && certificates.tlsCert && certificates.tlsKey 
                        && forge.pki.certificateFromPem(certificates.caCert) && forge.pki.privateKeyFromPem(certificates.caKey) && forge.pki.certificateFromPem(certificates.tlsCert) && forge.pki.privateKeyFromPem(certificates.tlsKey))) {
                        throw new Error('Invalid KubeConfig or Certificates');
                }
                return null;
            }).mockResolvedValue(null);
            const restartWebhookReplicaset = jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockResolvedValue(null);

            const operationId = 'operationId';
            await CertificateManager.ReconcileWebhookAndCertificates(operationId, mockClusterArmId, mockClusterArmRegion);

            expect(isValidCertificate).toHaveBeenCalledWith(operationId, realCertObj.caCert, realCertObj, mockClusterArmId, mockClusterArmRegion);
            expect(getMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
            expect(getSecretDetails).toHaveBeenCalledWith(operationId, mockKubeConfig);

            expect(generateHostCertificate).toHaveBeenCalled();
            expect(patchWebhookAndCertificates).toHaveBeenCalled();
            expect(restartWebhookReplicaset).toBeCalled();
        });
    });

    describe('PatchMutatingWebhook', () => {
        it('should patch mutating webhook', async () => {
            // Arrange
            const operationId = 'operationId';
            const mockKubeConfig = new k8s.KubeConfig();
            const mockCertificate: WebhookCertData = {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsCert: 'mockTLSCert',
                tlsKey: 'mockTLSKey',
            };
            const mutatingwebhookobject = {
                response: null,
                body: {
                    webhooks: [
                        {
                            name: 'app-monitoring-webhook',
                            clientConfig: {
                                caBundle: ''
                            }
                        } as k8s.V1MutatingWebhook
                    ]
                }
            };
            const readMutatingWebhookConfiguration  = jest.spyOn(k8s.AdmissionregistrationV1Api.prototype, 'readMutatingWebhookConfiguration').mockResolvedValue(mutatingwebhookobject);
            const mutatingwebhookobjectBodyCopy: k8s.V1MutatingWebhookConfiguration = JSON.parse(JSON.stringify(mutatingwebhookobject.body));
            const patchMutatingWebhookConfiguration  = jest.spyOn(k8s.AdmissionregistrationV1Api.prototype, 'patchMutatingWebhookConfiguration').mockResolvedValue(null);
            mutatingwebhookobjectBodyCopy.webhooks[0].clientConfig.caBundle = Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64');
            jest.spyOn(k8s.KubeConfig.prototype, 'makeApiClient').mockReturnValue(new k8s.AdmissionregistrationV1Api());

            // Mock the methods in CertificateManager
            jest.spyOn(CertificateManager, 'PatchMutatingWebhook');
            
            // Act
            await CertificateManager.PatchMutatingWebhook(operationId, mockKubeConfig, mockCertificate);
            mutatingwebhookobject.body.webhooks[0].clientConfig.caBundle = Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64');

            // Assert
            expect(readMutatingWebhookConfiguration).toHaveBeenCalledWith('app-monitoring-webhook');
            expect(patchMutatingWebhookConfiguration).toHaveBeenCalledWith('app-monitoring-webhook', mutatingwebhookobjectBodyCopy, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        });
    });

    describe('PatchWebhookAndCertificates', () => {
        it('should patch webhook and certificates', async () => {
            // Arrange
            const operationId = 'operationId';
            const mockKubeConfig = new k8s.KubeConfig();
            const mockCertificate: WebhookCertData = {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsCert: 'mockTLSCert',
                tlsKey: 'mockTLSKey',
            };
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';
            const patchMutatingWebhook = jest.spyOn(CertificateManager, 'PatchMutatingWebhook').mockResolvedValue(null);
            const patchSecretStore = jest.spyOn(CertificateManager, 'PatchSecretStore').mockResolvedValue(null);
            jest.spyOn(CertificateManager as any, 'RestartWebhookReplicaset').mockResolvedValue(null);

            // Act
            await (CertificateManager as any).PatchWebhookAndCertificates(operationId, mockKubeConfig, mockCertificate, clusterArmId, clusterArmRegion);

            // Assert
            expect(patchMutatingWebhook).toHaveBeenCalledWith(operationId, mockKubeConfig, mockCertificate);
            expect(patchSecretStore).toHaveBeenCalledWith(operationId, mockKubeConfig, mockCertificate);
        });
    });

    describe('PatchSecretStore', () => {
        it('should patch secret store', async () => {
            // Arrange
            const operationId = 'operationId';
            const mockKubeConfig = new k8s.KubeConfig();
            const mockCertificate: WebhookCertData = {
                caCert: 'mockCACert',
                caKey: 'mockCAKey',
                tlsCert: 'mockTLSCert',
                tlsKey: 'mockTLSKey',
            };
            const secretObject = {
                response: null,
                body: {
                    data: {
                        'ca.cert': '',
                        'ca.key': '',
                        'tls.cert': '',
                        'tls.key': ''
                    }
                }
            };
            const readNamespacedSecret = jest.spyOn(k8s.CoreV1Api.prototype, 'readNamespacedSecret').mockResolvedValue(secretObject);
            const patchNamespacedSecret = jest.spyOn(k8s.CoreV1Api.prototype, 'patchNamespacedSecret').mockResolvedValue(null);
            jest.spyOn(k8s.KubeConfig.prototype, 'makeApiClient').mockReturnValue(new k8s.CoreV1Api());

            // Mock the methods in CertificateManager
            jest.spyOn(CertificateManager, 'PatchSecretStore');
            
            // Act
            await CertificateManager.PatchSecretStore(operationId, mockKubeConfig, mockCertificate);

            // Assert
            expect(readNamespacedSecret).toHaveBeenCalledWith('app-monitoring-webhook-cert', 'kube-system');
            expect(patchNamespacedSecret).toHaveBeenCalledWith('app-monitoring-webhook-cert', 'kube-system', {
                data: {
                    'ca.cert': Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64'),
                    'ca.key': Buffer.from(mockCertificate.caKey, 'utf-8').toString('base64'),
                    'tls.cert': Buffer.from(mockCertificate.tlsCert, 'utf-8').toString('base64'),
                    'tls.key': Buffer.from(mockCertificate.tlsKey, 'utf-8').toString('base64')
                }
            }, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        });
    });

    describe('RestartWebhookReplicaset', () => {
        it('should restart webhook replicaset', async () => {
            // Arrange
            const operationId = 'operationId';
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';
            const mockKubeConfig = new k8s.KubeConfig();
            const replicaSetList = {
                body: {
                    items: [{
                            metadata: {
                                name: 'app-monitoring-webhook',
                                namespace: 'kube-system'
                            },
                            spec: {
                                selector: {
                                    matchLabels: {
                                        app: 'app-monitoring-webhook'
                                    }
                                },
                                template: {
                                    metadata: {
                                        name: 'app-monitoring-webhook',
                                        annotations: {
                                            'anno1': 'anno1'
                                        }
                                    }
                                }
                            }
                        } as k8s.V1ReplicaSet
                    ]} as k8s.V1ReplicaSetList
            } as any;
            const updatedReplicaSet: k8s.V1ReplicaSet = JSON.parse(JSON.stringify(replicaSetList.body.items[0]));
            jest.spyOn(Date.prototype, 'toISOString').mockReturnValue('GivenDate');
            updatedReplicaSet.spec.template.metadata = {
                name: 'app-monitoring-webhook',
                annotations: {
                    'anno1': 'anno1',
                    'kubectl.kubernetes.io/restartedAt': 'GivenDate'
                }
            };
            const listNamespacedReplicaSet = jest.spyOn(k8s.AppsV1Api.prototype, 'listNamespacedReplicaSet').mockResolvedValue(replicaSetList);
            const replaceNamespacedReplicaSet = jest.spyOn(k8s.AppsV1Api.prototype, 'replaceNamespacedReplicaSet').mockResolvedValue(null);
            jest.spyOn(k8s.KubeConfig.prototype, 'makeApiClient').mockReturnValue(new k8s.AppsV1Api());
            
            // Act
            await (CertificateManager as any).RestartWebhookReplicaset(operationId, mockKubeConfig, clusterArmId, clusterArmRegion);

            // Assert
            expect(listNamespacedReplicaSet).toHaveBeenCalledWith('kube-system');
            expect(replaceNamespacedReplicaSet).toHaveBeenCalledWith('app-monitoring-webhook', 'kube-system', updatedReplicaSet);
        });
    });

    describe('GenerateCACertificate', () => {
        it('should generate a CA certificate', async () => {
            jest.spyOn(Date, 'now').mockReturnValue(0);
            const caCert: forge.pki.Certificate = (CertificateManager as any).GenerateCACertificate();
            expect(caCert.subject.attributes[0].value).toStrictEqual('applicationinsights-ca');
            expect(caCert.subject.attributes[0].shortName).toStrictEqual('CN');
            expect(caCert.extensions[0].name).toStrictEqual('basicConstraints');
            expect(caCert.extensions[0].cA).toBeTruthy();
            expect(caCert.extensions[1].name).toStrictEqual('subjectKeyIdentifier');
            expect(caCert.extensions[2].name).toStrictEqual('keyUsage');
            expect(caCert.validity.notBefore).toStrictEqual(new Date(0 - (5 * 60 * 1000)));
            expect(caCert.validity.notAfter).toStrictEqual(new Date(2 * 365 * 24 * 60 * 60 * 1000));
        });
    });

    describe('GenerateHostCertificate', () => { 
        it('should generate a host certificate', async () => {
            jest.spyOn(Date, 'now').mockReturnValue(0);
            const caCert = (CertificateManager as any).GenerateCACertificate();
            const hostCert: forge.pki.Certificate = (CertificateManager as any).GenerateHostCertificate(caCert);
            expect(hostCert.subject.attributes[0].value).toStrictEqual('app-monitoring-webhook-service.kube-system.svc');
            expect(hostCert.subject.attributes[0].shortName).toStrictEqual('CN');
            expect(hostCert.extensions[0].name).toStrictEqual('basicConstraints');
            expect(hostCert.extensions[0].cA).toBeFalsy();
            expect(hostCert.extensions[1].name).toStrictEqual('authorityKeyIdentifier');
            expect(hostCert.extensions[2].name).toStrictEqual('keyUsage');
            expect(hostCert.extensions[3].name).toStrictEqual('extKeyUsage');
            expect(hostCert.extensions[4].name).toStrictEqual('subjectAltName');
            expect(hostCert.validity.notBefore).toStrictEqual(new Date(0 - (5 * 60 * 1000)));
            expect(hostCert.validity.notAfter).toStrictEqual(new Date(2 * 365 * 24 * 60 * 60 * 1000));
            expect(caCert.verify(hostCert)).toBeTruthy();
        });
    });
});

