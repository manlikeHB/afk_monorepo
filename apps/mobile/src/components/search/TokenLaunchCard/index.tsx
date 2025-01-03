import {NDKEvent, NDKUserProfile} from '@nostr-dev-kit/ndk';
import {useNavigation} from '@react-navigation/native';
import {useAccount} from '@starknet-react/core';
import {useProfile} from 'afk_nostr_sdk';
import * as Clipboard from 'expo-clipboard';
import {ImageSourcePropType, TouchableOpacity, View, Button} from 'react-native';

import {CopyIconStack} from '../../../assets/icons';
import {useStyles, useTheme, useWindowDimensions} from '../../../hooks';
import {useToast} from '../../../hooks/modals';
import {MainStackNavigationProps} from '../../../types';
import {TokenDeployInterface, TokenLaunchInterface} from '../../../types/keys';
import {feltToAddress} from '../../../utils/format';
// import {Button} from '../..';
import {Text} from '../../Text';
import stylesheet from './styles';
import { useMemo } from 'react';

export type LaunchCoinProps = {
  imageProps?: ImageSourcePropType;
  name?: string;
  event?: NDKEvent;
  profileProps?: NDKUserProfile;
  token?: TokenDeployInterface;
  dataMeged?: LaunchCoinProps;
  launch?: TokenLaunchInterface;
  isViewDetailDisabled?: boolean;
  isTokenOnly?: boolean;
};

enum AmountType {
  QUOTE_AMOUNT,
  COIN_AMOUNT_TO_BUY,
}

export const TokenLaunchCard: React.FC<LaunchCoinProps> = ({
  token,
  launch,
  imageProps,
  name,
  profileProps,
  event,
  isViewDetailDisabled,
  isTokenOnly,
}) => {
  const {data: profile} = useProfile({publicKey: event?.pubkey});
  const account = useAccount();
  const {showToast} = useToast();
  const {theme} = useTheme();
  const styles = useStyles(stylesheet);
  const navigation = useNavigation<MainStackNavigationProps>();

  const handleCopy = async () => {
    if (!token?.memecoin_address) return;
    await Clipboard.setStringAsync(token?.memecoin_address);
    showToast({type: 'info', title: 'Copied to clipboard'});
  };

  const dimensions = useWindowDimensions();
  const isDesktop = useMemo(() => {
    return dimensions.width >= 1024;
  }, [dimensions]);

  return (
    <View style={[styles.container, isDesktop && styles.containerDesktop]}>
      <View style={styles.header}>
        <Text style={styles.tokenName}>{token?.name || 'Unnamed Token'}</Text>
        {token?.symbol ? <Text style={styles.tokenSymbol}>{token.symbol}</Text> : null}
        <Text style={styles.price}>${Number(token?.price || 0).toFixed(4)}</Text>
      </View>

      {!isViewDetailDisabled && (
        <>
          {!isTokenOnly && (
            <TouchableOpacity
              onPress={() => {
                if (token && token?.memecoin_address) {
                  navigation.navigate('LaunchDetail', {
                    coinAddress: token?.memecoin_address,
                  });
                }
              }}
              style={styles.actionButton}
            >
              <Text style={styles.actionButtonText}>View details</Text>
            </TouchableOpacity>
          )}
          {isTokenOnly && (
            <TouchableOpacity
              onPress={() => {
                if (token && token?.memecoin_address) {
                  navigation.navigate('LaunchDetail', {
                    coinAddress: token?.memecoin_address,
                  });
                }
              }}
              style={styles.actionButton}
            >
              <Text style={styles.actionButtonText}>View token page</Text>
            </TouchableOpacity>
          )}
        </>
      )}
    </View>
  );
};
