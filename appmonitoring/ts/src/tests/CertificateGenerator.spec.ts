import { CertificateManager, WebhookCertData } from '../CertificateGenerator.js';
import * as k8s from '@kubernetes/client-node';
import forge from 'node-forge';
import { WebhookName } from '../Constants.js';

describe('CertificateManager', () => {
    let kubeConfig: k8s.KubeConfig;

    beforeEach(() => {
        kubeConfig = new k8s.KubeConfig();
        // Set up kubeConfig with necessary configurations
    });

    // describe('GenerateCACertificate', () => {
    //     it('should generate a CA certificate', async () => {
    //         const caCert = await CertificateManager.GenerateCACertificate();
    //         expect(caCert).toBeInstanceOf(forge.pki.Certificate);
    //     });

    //     it('should generate a CA certificate with existing key pair', async () => {
    //         const existingKeyPair = forge.pki.rsa.generateKeyPair(2048);
    //         const caCert = await CertificateManager.GenerateCACertificate(existingKeyPair);
    //         expect(caCert).toBeInstanceOf(forge.pki.Certificate);
    //     });
    // });

    // describe('GenerateHostCertificate', () => {
    //     it('should generate a host certificate', async () => {
    //         const caCert = forge.pki.createCertificate();
    //         const hostCert = await CertificateManager.GenerateHostCertificate(caCert);
    //         expect(hostCert).toBeInstanceOf(forge.pki.Certificate);
    //     });
    // });

    // Add more test cases for other methods in CertificateManager

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
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';
            const mutatingwebhookobject = {
                response: null,
                body: {
                    webhooks: [
                        {
                            name: WebhookName,
                            clientConfig: {
                                caBundle: ''
                            }
                        } as k8s.V1MutatingWebhook
                    ]
                }
            };
            const readMutatingWebhookConfiguration  = jest.spyOn(k8s.AdmissionregistrationV1Api.prototype, 'readMutatingWebhookConfiguration').mockResolvedValue(mutatingwebhookobject);
            const patchMutatingWebhookConfiguration  = jest.spyOn(k8s.AdmissionregistrationV1Api.prototype, 'patchMutatingWebhookConfiguration').mockResolvedValue(null);
            const mockApiClient = jest.spyOn(k8s.KubeConfig.prototype, 'makeApiClient').mockReturnValue(new k8s.AdmissionregistrationV1Api());

            // Mock the methods in CertificateManager
            jest.spyOn(CertificateManager, 'PatchMutatingWebhook');
            
            // Act
            await CertificateManager.PatchMutatingWebhook(operationId, mockKubeConfig, mockCertificate);
            mutatingwebhookobject.body.webhooks[0].clientConfig.caBundle = Buffer.from(mockCertificate.caCert, 'utf-8').toString('base64');

            // Assert
            expect(readMutatingWebhookConfiguration).toHaveBeenCalledWith(WebhookName);
            expect(patchMutatingWebhookConfiguration).toHaveBeenCalledWith(WebhookName, mutatingwebhookobject.body, undefined, undefined, undefined, undefined, undefined, {
                headers: { 'Content-Type' : 'application/strategic-merge-patch+json' }
            });
        });
    });

    describe('CreateWebhookAndCertificates', () => {
        it('should create webhook and certificates', async () => {
            const operationId = 'operationId';
            const clusterArmId = 'clusterArmId';
            const clusterArmRegion = 'clusterArmRegion';



            // Mock necessary dependencies and perform the test

            // Assert the expected behavior
        });
    });

    // describe('ReconcileWebhookAndCertificates', () => {
    //     it('should reconcile webhook and certificates', async () => {
    //         // Arrange
    //         const operationId = 'operationId';
    //         const clusterArmId = 'clusterArmId';
    //         const clusterArmRegion = 'clusterArmRegion';

    //         // Mock necessary dependencies
    //         const mockKubeConfig = new k8s.KubeConfig();
    //         const mockCertificate: WebhookCertData = {
    //             caCert: 'mockCACert',
    //             caKey: 'mockCAKey',
    //             tlsCert: 'mockTLSCert',
    //             tlsKey: 'mockTLSKey'
    //         };
    //         const mockReconciledCertData: WebhookCertData = {
    //             caCert: 'reconciledCACert',
    //             caKey: 'reconciledCAKey',
    //             tlsCert: 'reconciledTLSCert',
    //             tlsKey: 'reconciledTLSKey'
    //         };
    //         const mockRestartedReplicaset = jest.fn();
    //         const mockPatchWebhookAndCertificates = jest.fn().mockResolvedValue(mockReconciledCertData);
    //         const mockIsValidateCertificate = jest.fn().mockReturnValue(true);
    //         const mockGetMutatingWebhookCABundle = jest.fn().mockResolvedValue('mockCABundle');

    //         // Mock the methods in CertificateManager
    //         jest.spyOn(CertificateManager, 'PatchMutatingWebhook').mockImplementation(mockPatchWebhookAndCertificates);
    //         jest.spyOn(CertificateManager, 'PatchSecretStore').mockImplementation(mockIsValidateCertificate);
    //         jest.spyOn(CertificateManager, 'GetMutatingWebhookCABundle').mockImplementation(mockGetMutatingWebhookCABundle);

    //         // Act
    //         await CertificateManager.ReconcileWebhookAndCertificates(operationId, clusterArmId, clusterArmRegion);

    //         // Assert
    //         expect(mockPatchWebhookAndCertificates).toHaveBeenCalledWith(operationId, mockKubeConfig, mockCertificate, clusterArmId, clusterArmRegion);
    //         expect(mockIsValidateCertificate).toHaveBeenCalledWith(operationId, 'mockCABundle', mockReconciledCertData, clusterArmId, clusterArmRegion);
    //         expect(mockRestartedReplicaset).toHaveBeenCalledWith(operationId, mockKubeConfig, clusterArmId, clusterArmRegion);
    //         expect(mockGetMutatingWebhookCABundle).toHaveBeenCalledWith(operationId, mockKubeConfig);
    //     });
    // });

    // Add more test cases for other methods in CertificateManager
});

