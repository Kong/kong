import { ChannelCredentials, Metadata } from '@grpc/grpc-js';

export interface GrpcConfig {
  address: string;
  channelCredentials: ChannelCredentials;
  meta: Metadata;
}
