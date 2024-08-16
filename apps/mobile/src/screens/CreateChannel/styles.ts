import {Spacing, ThemedStyleSheet} from '../../styles';

export default ThemedStyleSheet((theme) => ({
  container: {
    flex: 1,
    backgroundColor: theme.colors.background,
    height:"100%"
  },

  form: {
    gap: Spacing.xsmall,
    paddingVertical: Spacing.medium,
    paddingHorizontal: Spacing.pagePadding,
  },
  gap: {
    height: Spacing.medium,
  },
  publicKeyInput: {
    color: theme.colors.primary,
  },
}));