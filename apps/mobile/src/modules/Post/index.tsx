import { NDKEvent } from '@nostr-dev-kit/ndk';
import { useNavigation } from '@react-navigation/native';
import { useQueryClient } from '@tanstack/react-query';
import { useMemo, useState } from 'react';
import { Image, Pressable, View } from 'react-native';
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withSequence,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { CommentIcon, LikeFillIcon, LikeIcon, RepostIcon } from '../../assets/icons';
import { Avatar, Icon, IconButton, Menu, Text } from '../../components';
import { useStyles, useTheme } from '../../hooks';
import { useProfile, useReact, useReactions, useReplyNotes, } from "afk_nostr_sdk"
import { useTipModal } from '../../hooks/modals';
// import { useAuth } from '../../store/auth';
import { useAuth } from 'afk_nostr_sdk';

import { MainStackNavigationProps } from '../../types';
import { getImageRatio, shortenPubkey } from '../../utils/helpers';
import { getElapsedTimeStringFull } from '../../utils/timestamp';
import stylesheet from './styles';

export type PostProps = {
  asComment?: boolean;
  event?: NDKEvent;
};

export const Post: React.FC<PostProps> = ({ asComment, event }) => {
  const repostedEvent = undefined;

  const { theme } = useTheme();
  const styles = useStyles(stylesheet);

  const navigation = useNavigation<MainStackNavigationProps>();

  const [dimensionsMedia, setMediaDimensions] = useState([250,300])
  const { publicKey } = useAuth();
  const { show: showTipModal } = useTipModal();
  const { data: profile } = useProfile({ publicKey: event?.pubkey });
  const reactions = useReactions({ noteId: event?.id });
  const userReaction = useReactions({ authors: [publicKey], noteId: event?.id });
  const comments = useReplyNotes({ noteId: event?.id });
  const react = useReact();
  const queryClient = useQueryClient();

  const [menuOpen, setMenuOpen] = useState(false);

  const scale = useSharedValue(1);
  const [isContentExpanded, setIsContentExpanded] = useState(false);

  const toggleExpandedContent = () => {
    setIsContentExpanded((prev) => !prev);
  };

  const isLiked = useMemo(
    () =>
      Array.isArray(userReaction.data) &&
      userReaction.data[0] &&
      userReaction.data[0]?.content !== '-',
    [userReaction.data],
  );

  const likes = useMemo(() => {
    if (!reactions.data) return 0;

    const likesCount = reactions.data.filter((reaction) => reaction.content !== '-').length;
    const dislikesCount = reactions.data.length - likesCount;
    return likesCount - dislikesCount;
  }, [reactions.data]);

  const postSource = useMemo(() => {
    if (!event?.tags) return;

    const imageTag = event.tags.find((tag) => tag[0] === 'image');
    if (!imageTag) return;
    /** @TODO finish good dimensions with correct ratio and base on the Platform */
    let dimensions = [250, 300]
    if (imageTag[2]) {
      dimensions = imageTag[2].split('x').map(Number)
      setMediaDimensions(dimensions)
    }
    return { uri: imageTag[1], width: dimensions[0], height: dimensions[1] };
  }, [event?.tags]);

  const animatedIconStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  const handleProfilePress = (userId?: string) => {
    if (userId) {
      navigation.navigate('Profile', { publicKey: userId });
    }
  };

  const handleNavigateToPostDetails = () => {
    if (!event?.id) return;
    navigation.navigate('PostDetail', { postId: event?.id, post: event });
  };

  const toggleLike = async () => {
    if (!event?.id) return;

    await react.mutateAsync(
      { event, type: isLiked ? 'dislike' : 'like' },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: ['reactions', event?.id] });

          scale.value = withSequence(
            withTiming(1.5, { duration: 100, easing: Easing.out(Easing.ease) }), // Scale up
            withSpring(1, { damping: 6, stiffness: 200 }), // Bounce back
          );
        },
      },
    );
  };

  const content = event?.content || '';
  const truncatedContent = content.length > 200 ? `${content.slice(0, 200)}...` : content;



  return (
    <View style={styles.container}>
      {repostedEvent && (
        <View style={styles.repost}>
          <RepostIcon color={theme.colors.textLight} height={18} />
          <Text color="textLight">Reposted</Text>
        </View>
      )}

      <View style={styles.info}>
        <View style={styles.infoUser}>
          <Pressable onPress={() => handleProfilePress(event?.pubkey)}>
            <Avatar
              size={asComment ? 40 : 50}
              source={
                profile?.image ? { uri: profile.image } : require('../../assets/degen-logo.png')
              }
            />
          </Pressable>

          <Pressable style={styles.infoProfile} onPress={handleNavigateToPostDetails}>
            <Text
              weight="bold"
              color="textStrong"
              fontSize={asComment ? 13 : 15}
              lineHeight={20}
              numberOfLines={1}
              ellipsizeMode="middle"
            >
              {profile?.displayName ??
                profile?.name ??
                profile?.nip05 ??
                shortenPubkey(event?.pubkey)}
            </Text>

            <View style={styles.infoDetails}>
              {(profile?.nip05 || profile?.name) && (
                <>
                  <Text
                    color="textLight"
                    fontSize={11}
                    lineHeight={16}
                    numberOfLines={1}
                    ellipsizeMode="tail"
                  >
                    @{profile?.nip05 ?? profile.name}
                  </Text>

                  <View style={styles.infoDetailsDivider} />
                </>
              )}

              <Text color="textLight" fontSize={11} lineHeight={16}>
                {getElapsedTimeStringFull((event?.created_at ?? Date.now()) * 1000)}
              </Text>
            </View>
          </Pressable>
        </View>

        <Pressable onPress={toggleLike}>
          <View style={styles.infoLikes}>
            <Animated.View style={animatedIconStyle}>
              {isLiked ? (
                <LikeFillIcon height={20} color={theme.colors.red} />
              ) : (
                <LikeIcon height={20} color={theme.colors.text} />
              )}
            </Animated.View>

            {likes > 0 && (
              <Text color="textSecondary" fontSize={11} lineHeight={16}>
                {likes} {likes === 1 ? 'like' : 'likes'}
              </Text>
            )}
          </View>
        </Pressable>
      </View>

      <View style={styles.content}>
        <Pressable onPress={handleNavigateToPostDetails}>
          <Text color="textStrong" fontSize={13} lineHeight={20}>
            {isContentExpanded ? content : truncatedContent}
          </Text>

          {content.length > 200 && (
            <Pressable onPress={toggleExpandedContent}>
              <Text style={styles.seeMore}>{isContentExpanded ? 'See less' : 'See more...'}</Text>
            </Pressable>
          )}

          {postSource && (
            <Image
              source={postSource}
              style={[
                styles.contentImage,
                {
                  // width:dimensionsMedia[0],
                  height:dimensionsMedia[1],
                  aspectRatio: getImageRatio(postSource.width, postSource.height)
                },
              ]}
            />
          )}
        </Pressable>
      </View>

      {/* TODO: check tags if it's: quote repost reply  */}

      {!asComment && (
        <View style={styles.footer}>
          <View style={{
            flex: 1,
            flexDirection: "row",
            alignItems: "baseline",
            gap: 10,
          }}>
            <Pressable onPress={handleNavigateToPostDetails}>
              <View style={styles.footerComments}>
                <CommentIcon height={20} color={theme.colors.textSecondary} />

                <Text color="textSecondary" fontSize={11} lineHeight={16}>
                  {comments.data?.pages.flat().length} comments
                </Text>
              </View>
            </Pressable>

            <Pressable
              style={{ marginHorizontal: 3 }}
              onPress={() => {
                if (!event) return;
                showTipModal(event);
              }}
            >
              <Icon name='CoinIcon'
                size={20}
                title='Tip'
                onPress={() => {
                  if (!event) return;

                  showTipModal(event);
                }}
              />

            </Pressable>
          </View>




          {/* <Pressable
            // style={styles.seeMore}
            onPress={() => {
              if (!event) return;

              showTipModal(event);
            }}
          >

            <Icon name='CoinIcon'
              size={24}
              title='Tip'
            />
          </Pressable> */}
          {/* 
          <Menu.Item
            label={profile?.username ? `Tip @${profile.username}` : 'Tip'}
            icon="CoinIcon"
            onPress={() => {
              if (!event) return;

              showTipModal(event);
              setMenuOpen(false);
            }}
          /> */}

          <Menu
            open={menuOpen}
            onClose={() => setMenuOpen(false)}
            handle={
              <IconButton icon="MoreHorizontalIcon" size={20} onPress={() => setMenuOpen(true)} />
            }
          >
            <Menu.Item label="Share" icon="ShareIcon" />
            <Menu.Item
              label={profile?.username ? `Tip @${profile.username}` : 'Tip'}
              icon="CoinIcon"
              onPress={() => {
                if (!event) return;

                showTipModal(event);
                setMenuOpen(false);
              }}
            />
          </Menu>
        </View>
      )}
    </View>
  );
};